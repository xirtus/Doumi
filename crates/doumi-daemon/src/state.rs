use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};

use doumi_core::config::ConfigManager;
use doumi_core::engine::RuleEngine;

use crate::db::ActionLogger;

pub struct DaemonState {
    pub config: ConfigManager,
    pub engine: RwLock<RuleEngine>,
    pub db: Mutex<ActionLogger>,
    pub dry_run: bool,
    pub watch_count: RwLock<usize>,
}

impl DaemonState {
    pub fn new(config: ConfigManager, db: ActionLogger, dry_run: bool) -> Arc<Self> {
        Arc::new(Self {
            engine: RwLock::new(RuleEngine::new(dry_run)),
            db: Mutex::new(db),
            dry_run,
            watch_count: RwLock::new(0),
            config,
        })
    }
}
