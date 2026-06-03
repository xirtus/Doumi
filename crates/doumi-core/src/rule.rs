use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::actions::Action;
use crate::conditions::Condition;

fn default_true() -> bool {
    true
}
fn default_depth() -> i32 {
    1
}
fn is_false(value: &bool) -> bool {
    !*value
}
fn default_condition_group() -> Condition {
    Condition::Group {
        match_mode: Default::default(),
        items: vec![],
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FolderConfig {
    pub path: String,
    #[serde(default)]
    pub recursive: bool,
    #[serde(default = "default_depth")]
    pub depth: i32,
    #[serde(default, skip_serializing_if = "is_false")]
    pub allow_project_roots: bool,
}

impl FolderConfig {
    pub fn expanded_path(&self) -> PathBuf {
        PathBuf::from(shellexpand::tilde(&self.path).as_ref())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerConfig {
    #[serde(default = "default_true")]
    pub on_add: bool,
    #[serde(default)]
    pub on_modify: bool,
    #[serde(default)]
    pub on_delete: bool,
    pub schedule: Option<String>,
}

impl Default for TriggerConfig {
    fn default() -> Self {
        Self {
            on_add: true,
            on_modify: false,
            on_delete: false,
            schedule: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuleConfig {
    pub id: String,
    pub name: String,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub folders: Vec<FolderConfig>,
    #[serde(default)]
    pub triggers: TriggerConfig,
    #[serde(default = "default_condition_group")]
    pub conditions: Condition,
    #[serde(default)]
    pub actions: Vec<Action>,
    #[serde(default = "default_true")]
    pub continue_matching: bool,
    #[serde(skip)]
    pub source_file: Option<PathBuf>,
}
