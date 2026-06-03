use std::sync::Arc;
use tracing::{info, warn};

use doumi_core::scope::scan_folder_files;

use crate::state::DaemonState;

pub async fn run_scheduler(state: Arc<DaemonState>) -> anyhow::Result<()> {
    use tokio_cron_scheduler::{Job, JobScheduler};

    let sched = JobScheduler::new().await?;
    let rules = state.config.load_all_rules();

    let mut job_count = 0;
    for rule in &rules {
        if !rule.enabled {
            continue;
        }
        let Some(schedule_str) = &rule.triggers.schedule else {
            continue;
        };
        if schedule_str.is_empty() {
            continue;
        }

        let rule_id = rule.id.clone();
        let state_clone = state.clone();

        let cron = normalize_cron(schedule_str);
        match Job::new_async(cron.as_str(), move |_uuid, _lock| {
            let rule_id = rule_id.clone();
            let state = state_clone.clone();
            Box::pin(async move {
                run_scheduled_scan(&rule_id, &state).await;
            })
        }) {
            Ok(job) => {
                sched.add(job).await?;
                job_count += 1;
                info!("Scheduled rule {:?} with cron {}", rule.name, schedule_str);
            }
            Err(e) => {
                warn!(
                    "Invalid schedule {:?} for rule {:?}: {e}",
                    schedule_str, rule.name
                );
            }
        }
    }

    if job_count > 0 {
        sched.start().await?;
        info!("Scheduler started with {job_count} jobs");
    }

    // Keep alive
    loop {
        tokio::time::sleep(tokio::time::Duration::from_secs(3600)).await;
    }
}

async fn run_scheduled_scan(rule_id: &str, state: &DaemonState) {
    info!("Scheduled scan for rule {rule_id}");
    let rules = state.config.load_all_rules();
    let Some(rule) = rules.iter().find(|r| r.id == rule_id) else {
        return;
    };

    let engine = state.engine.read().await;
    let db = state.db.lock().await;

    for folder in &rule.folders {
        let fp = folder.expanded_path();
        if !fp.exists() {
            continue;
        }
        for path in scan_folder_files(folder) {
            let results = engine.process_file(&path, Some(&fp));
            for result in &results {
                if result.matched && state.config.settings.log_actions {
                    let _ = db.log_result(result);
                }
            }
        }
    }
}

fn normalize_cron(s: &str) -> String {
    // tokio-cron-scheduler uses 6-field cron (with seconds) or 5-field
    // If string looks like interval (e.g. "1h", "30m"), convert to cron
    if !s.contains(' ') {
        return parse_interval_to_cron(s).unwrap_or_else(|| "0 0 * * * *".to_string());
    }
    let parts: Vec<&str> = s.split_whitespace().collect();
    if parts.len() == 5 {
        // Standard 5-field cron: add seconds field
        format!("0 {s}")
    } else {
        s.to_string()
    }
}

fn parse_interval_to_cron(s: &str) -> Option<String> {
    let s = s.trim().to_lowercase();
    if let Some(n) = s.strip_suffix('h') {
        let h: u32 = n.parse().ok()?;
        return Some(format!("0 0 */{h} * * *"));
    }
    if let Some(n) = s.strip_suffix('m') {
        let m: u32 = n.parse().ok()?;
        return Some(format!("0 */{m} * * * *"));
    }
    if let Some(n) = s.strip_suffix('d') {
        let _d: u32 = n.parse().ok()?;
        return Some(format!("0 0 0 */{_d} * *"));
    }
    None
}
