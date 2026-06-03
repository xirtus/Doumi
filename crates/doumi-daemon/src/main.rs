mod db;
mod ipc;
mod scheduler;
mod state;
mod watcher;

use clap::Parser;
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

use doumi_core::config::ConfigManager;
use doumi_core::scope::scan_folder_files;

use crate::db::ActionLogger;
use crate::state::DaemonState;

#[derive(Parser)]
#[command(name = "doumid", about = "Doumi daemon")]
struct Args {
    #[arg(long)]
    dry_run: bool,
    #[arg(long)]
    debug: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    let level = if args.debug { "debug" } else { "info" };
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::new(level))
        .init();

    let config = ConfigManager::new()?;
    let db = ActionLogger::open(&config.db_path(), config.settings.max_log_entries)?;
    let dry_run = args.dry_run || config.settings.dry_run;

    let state = DaemonState::new(config, db, dry_run);

    let socket_path = state.config.ipc_socket_path();
    let pid_file = socket_path.with_extension("pid");
    let _ = std::fs::write(&pid_file, std::process::id().to_string());

    {
        let rules = state.config.load_all_rules();
        state.engine.write().await.reload(rules);
    }

    if state.config.settings.scan_on_start {
        let sc = state.clone();
        tokio::spawn(async move { startup_scan(&sc).await });
    }

    info!("doumid starting{}", if dry_run { " (dry-run)" } else { "" });

    let w = state.clone();
    let s = state.clone();
    let i = state.clone();
    let sock = socket_path.clone();

    let watcher_h = tokio::spawn(async move {
        if let Err(e) = watcher::run_watcher(w).await {
            warn!("Watcher: {e}");
        }
    });
    let sched_h = tokio::spawn(async move {
        if let Err(e) = scheduler::run_scheduler(s).await {
            warn!("Scheduler: {e}");
        }
    });
    let ipc_h = tokio::spawn(async move {
        if let Err(e) = ipc::run_ipc(&sock, i).await {
            warn!("IPC: {e}");
        }
    });

    info!("doumid running");

    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate())?;
        let mut sigint = signal(SignalKind::interrupt())?;
        tokio::select! {
            _ = sigterm.recv() => info!("SIGTERM received"),
            _ = sigint.recv()  => info!("SIGINT received"),
        }
    }
    #[cfg(not(unix))]
    {
        info!("Press Ctrl+C to stop");
        tokio::signal::ctrl_c().await?;
        info!("Ctrl+C received");
    }

    info!("Shutting down…");
    watcher_h.abort();
    sched_h.abort();
    ipc_h.abort();
    let _ = std::fs::remove_file(&socket_path);
    let _ = std::fs::remove_file(&pid_file);
    info!("Goodbye");
    Ok(())
}

async fn startup_scan(state: &DaemonState) {
    let rules = state.config.load_all_rules();
    let engine = state.engine.read().await;
    let db = state.db.lock().await;

    for rule in &rules {
        if !rule.enabled || !rule.triggers.on_add {
            continue;
        }
        for folder in &rule.folders {
            let fp = folder.expanded_path();
            if !fp.exists() {
                continue;
            }
            for path in scan_folder_files(folder) {
                let results = engine.process_file(&path, Some(&fp));
                for r in &results {
                    if r.matched && state.config.settings.log_actions {
                        let _ = db.log_result(r);
                    }
                }
            }
        }
    }
}
