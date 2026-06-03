use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::error;

use crate::loader::{load_rule_file, save_rule_file};
use crate::rule::RuleConfig;

fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from(".config"))
        .join("doumi")
}

fn default_log_level() -> String {
    "INFO".to_string()
}
fn default_true() -> bool {
    true
}
fn default_max_log() -> usize {
    10000
}
fn default_socket() -> String {
    #[cfg(unix)]
    {
        dirs::runtime_dir()
            .or_else(|| dirs::home_dir().map(|h| h.join(".local").join("run")))
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join("doumi.sock")
            .to_string_lossy()
            .to_string()
    }
    #[cfg(windows)]
    {
        // On Windows, store the socket marker next to config
        dirs::data_local_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("doumi")
            .join("doumi.sock")
            .to_string_lossy()
            .to_string()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_log_level")]
    pub log_level: String,
    #[serde(default = "default_true")]
    pub log_actions: bool,
    #[serde(default = "default_max_log")]
    pub max_log_entries: usize,
    #[serde(default)]
    pub dry_run: bool,
    #[serde(default = "default_socket")]
    pub ipc_socket: String,
    #[serde(default = "default_true")]
    pub scan_on_start: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            log_level: default_log_level(),
            log_actions: true,
            max_log_entries: default_max_log(),
            dry_run: false,
            ipc_socket: default_socket(),
            scan_on_start: true,
        }
    }
}

pub struct ConfigManager {
    pub config_dir: PathBuf,
    pub rules_dir: PathBuf,
    pub scripts_dir: PathBuf,
    pub logs_dir: PathBuf,
    pub settings_file: PathBuf,
    pub settings: Settings,
}

impl ConfigManager {
    pub fn new() -> anyhow::Result<Self> {
        let config_dir = config_dir();
        let rules_dir = config_dir.join("rules");
        let scripts_dir = config_dir.join("scripts");
        let logs_dir = config_dir.join("logs");
        let settings_file = config_dir.join("settings.json");

        for d in [&config_dir, &rules_dir, &scripts_dir, &logs_dir] {
            std::fs::create_dir_all(d)?;
        }

        let settings = if settings_file.exists() {
            std::fs::read_to_string(&settings_file)
                .ok()
                .and_then(|t| serde_json::from_str(&t).ok())
                .unwrap_or_default()
        } else {
            Settings::default()
        };

        Ok(Self {
            config_dir,
            rules_dir,
            scripts_dir,
            logs_dir,
            settings_file,
            settings,
        })
    }

    pub fn ipc_socket_path(&self) -> PathBuf {
        let p = PathBuf::from(&self.settings.ipc_socket);
        if let Some(parent) = p.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        p
    }

    pub fn db_path(&self) -> PathBuf {
        self.logs_dir.join("doumi.db")
    }

    pub fn load_all_rules(&self) -> Vec<RuleConfig> {
        let mut rules: Vec<RuleConfig> = std::fs::read_dir(&self.rules_dir)
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter(|e| e.path().extension().map_or(false, |x| x == "json"))
                    .filter_map(|e| {
                        load_rule_file(&e.path())
                            .map_err(|err| {
                                error!("Failed to load {:?}: {}", e.path(), err);
                                err
                            })
                            .ok()
                    })
                    .collect()
            })
            .unwrap_or_default();
        rules.sort_by_key(|r| r.priority);
        rules
    }

    pub fn save_rule(&self, rule: &mut RuleConfig) -> anyhow::Result<PathBuf> {
        let safe_id: String = rule
            .id
            .chars()
            .map(|c| {
                if c.is_alphanumeric() || c == '-' || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect();
        let path = self.rules_dir.join(format!("{safe_id}.json"));
        save_rule_file(rule, &path)?;
        rule.source_file = Some(path.clone());
        Ok(path)
    }

    pub fn get_rule_by_id(&self, rule_id: &str) -> Option<RuleConfig> {
        self.load_all_rules()
            .into_iter()
            .find(|r| r.id == rule_id || r.id.starts_with(rule_id))
    }

    pub fn delete_rule(&self, rule_id: &str) -> bool {
        let safe_id: String = rule_id
            .chars()
            .map(|c| {
                if c.is_alphanumeric() || c == '-' || c == '_' {
                    c
                } else {
                    '_'
                }
            })
            .collect();
        let path = self.rules_dir.join(format!("{safe_id}.json"));
        if path.exists() {
            let _ = std::fs::remove_file(&path);
            return true;
        }
        if let Ok(entries) = std::fs::read_dir(&self.rules_dir) {
            for entry in entries.filter_map(|e| e.ok()) {
                if let Ok(rule) = load_rule_file(&entry.path()) {
                    if rule.id == rule_id {
                        let _ = std::fs::remove_file(entry.path());
                        return true;
                    }
                }
            }
        }
        false
    }

    pub fn save_settings(&mut self) -> anyhow::Result<()> {
        let text = serde_json::to_string_pretty(&self.settings)?;
        std::fs::write(&self.settings_file, text)?;
        Ok(())
    }

    pub fn set_setting(&mut self, key: &str, value: serde_json::Value) -> anyhow::Result<()> {
        let mut map: serde_json::Map<String, serde_json::Value> =
            serde_json::to_value(&self.settings)
                .and_then(|v| serde_json::from_value(v))
                .unwrap_or_default();
        map.insert(key.to_string(), value);
        self.settings = serde_json::from_value(serde_json::Value::Object(map))?;
        self.save_settings()
    }
}
