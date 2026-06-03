use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use tokio::sync::mpsc;
use tracing::{info, warn};

use doumi_core::rule::RuleConfig;

use crate::state::DaemonState;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TriggerEvent {
    OnAdd,
    OnModify,
    OnDelete,
}

pub async fn run_watcher(state: Arc<DaemonState>) -> anyhow::Result<()> {
    let (tx, mut rx) = mpsc::channel::<Result<Event, notify::Error>>(512);

    let mut watcher = RecommendedWatcher::new(
        move |res| {
            let _ = tx.blocking_send(res);
        },
        Config::default().with_poll_interval(Duration::from_secs(2)),
    )?;

    // Register watches from current rules
    {
        let rules = state.config.load_all_rules();
        let count = watch_rules(&mut watcher, &rules);
        *state.watch_count.write().await = count;
    }

    info!("File watcher started");

    while let Some(res) = rx.recv().await {
        match res {
            Ok(event) => {
                let trigger = match event.kind {
                    EventKind::Create(_) => Some(TriggerEvent::OnAdd),
                    EventKind::Modify(_) => Some(TriggerEvent::OnModify),
                    EventKind::Remove(_) => Some(TriggerEvent::OnDelete),
                    _ => None,
                };

                if let Some(trigger) = trigger {
                    for path in &event.paths {
                        process_event(path.clone(), trigger, &state).await;
                    }
                }
            }
            Err(e) => {
                warn!("Watcher error: {e}");
            }
        }
    }

    Ok(())
}

fn watch_rules(watcher: &mut RecommendedWatcher, rules: &[RuleConfig]) -> usize {
    let mut count = 0;
    let mut watches = std::collections::BTreeMap::<PathBuf, bool>::new();

    for rule in rules {
        if !rule.enabled {
            continue;
        }
        for folder in &rule.folders {
            let path = folder.expanded_path();
            watches
                .entry(path)
                .and_modify(|recursive| *recursive |= folder.recursive)
                .or_insert(folder.recursive);
        }
    }

    for (path, recursive) in watches {
        if !path.exists() {
            warn!("Watch path does not exist: {}", path.display());
            continue;
        }
        let mode = if recursive {
            RecursiveMode::Recursive
        } else {
            RecursiveMode::NonRecursive
        };
        if let Err(e) = watcher.watch(&path, mode) {
            warn!("Failed to watch {}: {e}", path.display());
        } else {
            info!(
                "Watching {}{}",
                path.display(),
                if recursive { " recursively" } else { "" }
            );
            count += 1;
        }
    }
    count
}

async fn process_event(path: PathBuf, trigger: TriggerEvent, state: &DaemonState) {
    // Check if any rule triggers on this event type
    let engine = state.engine.read().await;
    let matching_rules: Vec<_> = engine
        .rules
        .iter()
        .filter(|r| match trigger {
            TriggerEvent::OnAdd => r.cfg.triggers.on_add,
            TriggerEvent::OnModify => r.cfg.triggers.on_modify,
            TriggerEvent::OnDelete => r.cfg.triggers.on_delete,
        })
        .collect();

    if matching_rules.is_empty() {
        return;
    }

    if trigger == TriggerEvent::OnDelete || !path.exists() {
        return;
    }

    let results = engine.process_file(&path, None);
    drop(engine);

    let db = state.db.lock().await;
    for result in &results {
        if result.matched {
            info!(
                "[{}] Rule {:?} matched {}",
                format!("{trigger:?}"),
                result.rule_name,
                path.file_name().unwrap_or_default().to_string_lossy()
            );
            if state.config.settings.log_actions {
                if let Err(e) = db.log_result(result) {
                    warn!("DB log error: {e}");
                }
            }
        }
    }
}
