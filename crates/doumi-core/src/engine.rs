use std::path::{Path, PathBuf};
use tracing::{error, warn};

use crate::models::{ActionResult, FileInfo, ProcessingResult};
use crate::rule::RuleConfig;
use crate::scope::{evaluate_path_scope, SkipReason};

pub struct CompiledRule {
    pub cfg: RuleConfig,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scope::scan_folder_files;
    use serde_json::json;
    use tempfile::tempdir;

    fn cleanup_rule(
        root: &Path,
        dest: &Path,
        recursive: bool,
        depth: i32,
        allow_project_roots: bool,
    ) -> RuleConfig {
        serde_json::from_value(json!({
            "id": "cleanup",
            "name": "Cleanup",
            "enabled": true,
            "priority": 0,
            "folders": [{
                "path": root.to_string_lossy(),
                "recursive": recursive,
                "depth": depth,
                "allow_project_roots": allow_project_roots
            }],
            "triggers": {
                "on_add": true,
                "on_modify": false,
                "on_delete": false,
                "schedule": null
            },
            "conditions": {
                "type": "extension",
                "operator": "is_one_of",
                "value": ["jpg", "png", "pdf", "md"]
            },
            "actions": [{
                "type": "move",
                "destination": dest.to_string_lossy(),
                "on_conflict": "rename",
                "create_parents": true
            }],
            "continue_matching": false
        }))
        .unwrap()
    }

    fn engine_with(rule: RuleConfig, dry_run: bool) -> RuleEngine {
        let mut engine = RuleEngine::new(dry_run);
        engine.load_rules(vec![rule]);
        engine
    }

    #[test]
    fn top_level_file_gets_matched_and_moved() {
        let tmp = tempdir().unwrap();
        let documents = tmp.path().join("Documents");
        let pictures = tmp.path().join("Pictures");
        std::fs::create_dir_all(&documents).unwrap();
        let image = documents.join("image.jpg");
        std::fs::write(&image, b"jpg").unwrap();

        let rule = cleanup_rule(&documents, &pictures, false, 1, false);
        let engine = engine_with(rule, false);

        let results = engine.process_file(&image, None);

        assert_eq!(results.len(), 1);
        assert!(results[0].matched);
        assert!(results[0].skip_reason.is_none());
        assert!(!image.exists());
        assert!(pictures.join("image.jpg").exists());
    }

    #[test]
    fn nested_project_tree_is_skipped_by_default() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let config = repo.join(".git").join("config");
        std::fs::write(&config, b"repo config").unwrap();

        let rule = cleanup_rule(&downloads, &tmp.path().join("Organized"), true, 4, false);
        let engine = engine_with(rule, true);

        let results = engine.process_file(&config, Some(&downloads));

        assert_eq!(results.len(), 1);
        assert!(!results[0].matched);
        let reason = results[0].skip_reason.as_deref().unwrap();
        assert!(reason.contains("protected project root"), "{reason}");
        assert!(reason.contains(".git"), "{reason}");
        assert!(config.exists());
    }

    #[test]
    fn watched_root_depth_limit_is_enforced() {
        let tmp = tempdir().unwrap();
        let desktop = tmp.path().join("Desktop");
        let project = desktop.join("Work").join("project");
        std::fs::create_dir_all(&project).unwrap();
        let report = project.join("report.md");
        std::fs::write(&report, b"notes").unwrap();

        let rule = cleanup_rule(&desktop, &tmp.path().join("Organized"), true, 1, false);
        let engine = engine_with(rule, true);

        let results = engine.process_file(&report, Some(&desktop));

        assert_eq!(results.len(), 1);
        assert!(!results[0].matched);
        let reason = results[0].skip_reason.as_deref().unwrap();
        assert!(reason.contains("outside allowed depth 1"), "{reason}");
        assert!(report.exists());
    }

    #[test]
    fn non_recursive_scope_explains_nested_skip_in_dry_run() {
        let tmp = tempdir().unwrap();
        let documents = tmp.path().join("Documents");
        let app = documents.join("App2");
        std::fs::create_dir_all(&app).unwrap();
        let image = app.join("image.jpg");
        std::fs::write(&image, b"jpg").unwrap();

        let rule = cleanup_rule(&documents, &tmp.path().join("Pictures"), false, 1, false);
        let engine = engine_with(rule, true);

        let results = engine.process_file(&image, Some(&documents));

        assert_eq!(results.len(), 1);
        assert!(!results[0].matched);
        let reason = results[0].skip_reason.as_deref().unwrap();
        assert!(reason.contains("nested folder protected"), "{reason}");
        assert!(image.exists());
    }

    #[test]
    fn live_and_scan_paths_share_project_protection() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let screenshot = repo.join("screenshot.png");
        std::fs::write(&screenshot, b"png").unwrap();

        let rule = cleanup_rule(&downloads, &tmp.path().join("Pictures"), true, 3, false);
        let engine = engine_with(rule, true);

        let live = engine.process_file(&screenshot, None);
        let scanned = engine.process_file(&screenshot, Some(&downloads));

        assert_eq!(live.len(), 1);
        assert_eq!(scanned.len(), 1);
        assert_eq!(live[0].skip_reason, scanned[0].skip_reason);
        assert!(live[0]
            .skip_reason
            .as_deref()
            .unwrap()
            .contains("protected project root"));
    }

    #[test]
    fn shared_scan_candidates_still_use_engine_safety_gate() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let top_level = downloads.join("screenshot.png");
        let nested = repo.join("image.png");
        std::fs::write(&top_level, b"png").unwrap();
        std::fs::write(&nested, b"png").unwrap();

        let rule = cleanup_rule(&downloads, &tmp.path().join("Pictures"), true, 3, false);
        let folder = rule.folders[0].clone();
        let engine = engine_with(rule, true);
        let candidates = scan_folder_files(&folder);

        assert!(candidates.contains(&top_level));
        assert!(candidates.contains(&nested));

        let results: Vec<_> = candidates
            .iter()
            .flat_map(|path| engine.process_file(path, Some(&downloads)))
            .collect();

        assert_eq!(results.iter().filter(|result| result.matched).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|result| result
                    .skip_reason
                    .as_deref()
                    .is_some_and(|reason| reason.contains("protected project root")))
                .count(),
            1
        );
    }

    #[test]
    fn project_tree_can_be_explicitly_opted_in() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let screenshot = repo.join("screenshot.png");
        std::fs::write(&screenshot, b"png").unwrap();

        let rule = cleanup_rule(&downloads, &tmp.path().join("Pictures"), true, 3, true);
        let engine = engine_with(rule, true);

        let results = engine.process_file(&screenshot, Some(&downloads));

        assert_eq!(results.len(), 1);
        assert!(results[0].matched);
        assert!(results[0].skip_reason.is_none());
    }
}

impl CompiledRule {
    pub fn new(cfg: RuleConfig) -> Self {
        Self { cfg }
    }

    pub fn matches(&self, file: &FileInfo) -> bool {
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.cfg.conditions.evaluate(file)
        })) {
            Ok(v) => v,
            Err(_) => {
                warn!("Condition eval panicked for rule {:?}", self.cfg.name);
                false
            }
        }
    }

    pub fn apply(&self, file: &FileInfo, dry_run: bool) -> ProcessingResult {
        let matched = self.matches(file);
        let mut result = ProcessingResult::new(
            file.path.clone(),
            self.cfg.id.clone(),
            self.cfg.name.clone(),
            matched,
            dry_run,
        );

        if !matched {
            return result;
        }

        let mut current = file.clone();
        for action in &self.cfg.actions {
            let ar: ActionResult = action.execute(&current, dry_run);

            // Update current FileInfo if move/rename succeeded
            if ar.success {
                if let Some(ref dest) = ar.destination {
                    if dest.exists() && matches!(ar.action_type.as_str(), "move" | "rename") {
                        if let Ok(updated) = FileInfo::from_path(dest) {
                            current = updated;
                        }
                    }
                }
            }

            if !ar.success {
                error!(
                    "Action {} failed in rule {:?}: {}",
                    ar.action_type, self.cfg.name, ar.error
                );
            }

            result.action_results.push(ar);
        }

        result
    }
}

pub struct RuleEngine {
    pub rules: Vec<CompiledRule>,
    pub dry_run: bool,
}

impl RuleEngine {
    pub fn new(dry_run: bool) -> Self {
        Self {
            rules: vec![],
            dry_run,
        }
    }

    pub fn load_rules(&mut self, configs: Vec<RuleConfig>) {
        let mut compiled: Vec<CompiledRule> = configs
            .into_iter()
            .filter(|c| c.enabled)
            .map(CompiledRule::new)
            .collect();
        compiled.sort_by_key(|r| r.cfg.priority);
        self.rules = compiled;
        tracing::info!("Loaded {} rules", self.rules.len());
    }

    pub fn reload(&mut self, configs: Vec<RuleConfig>) {
        self.load_rules(configs);
    }

    pub fn process_file(
        &self,
        path: &Path,
        watched_from: Option<&PathBuf>,
    ) -> Vec<ProcessingResult> {
        if !path.exists() {
            return vec![];
        }

        let file = match FileInfo::from_path(path) {
            Ok(f) => f,
            Err(e) => {
                warn!("Cannot stat {}: {}", path.display(), e);
                return vec![];
            }
        };

        let mut results = Vec::new();

        for rule in &self.rules {
            if !rule.cfg.folders.is_empty() {
                let mut scoped = false;
                let mut skip_reason = None;

                for folder in &rule.cfg.folders {
                    let decision = evaluate_path_scope(path, folder);

                    if let Some(base) = watched_from {
                        if decision.watched_root != *base
                            && !base.starts_with(&decision.watched_root)
                        {
                            continue;
                        }
                    }

                    match decision.skip_reason {
                        None => {
                            scoped = true;
                            break;
                        }
                        Some(SkipReason::OutsideWatchedRoot { .. }) => {}
                        Some(reason) => {
                            skip_reason.get_or_insert_with(|| reason.to_string());
                        }
                    }
                }

                if !scoped {
                    if let Some(reason) = skip_reason {
                        results.push(ProcessingResult::skipped(
                            file.path.clone(),
                            rule.cfg.id.clone(),
                            rule.cfg.name.clone(),
                            self.dry_run,
                            reason,
                        ));
                    }
                    continue;
                }
            }

            let result = rule.apply(&file, self.dry_run);
            let stop = result.matched && !rule.cfg.continue_matching;
            results.push(result);
            if stop {
                break;
            }
        }

        results
    }
}
