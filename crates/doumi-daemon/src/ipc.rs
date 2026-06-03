use serde::Serialize;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixListener;
use tracing::{info, warn};

use doumi_core::engine::RuleEngine;
use doumi_core::models::{ActionResult, ProcessingResult};
use doumi_core::rule::{FolderConfig, RuleConfig};
use doumi_core::scope::scan_folder_files;

use crate::state::DaemonState;

pub async fn run_ipc(socket_path: &Path, state: Arc<DaemonState>) -> anyhow::Result<()> {
    if socket_path.exists() {
        std::fs::remove_file(socket_path)?;
    }
    let listener = UnixListener::bind(socket_path)?;
    info!("IPC listening at {}", socket_path.display());

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let state = state.clone();
                tokio::spawn(async move {
                    handle_client(stream, state).await;
                });
            }
            Err(e) => {
                warn!("IPC accept error: {e}");
            }
        }
    }
}

async fn handle_client(stream: tokio::net::UnixStream, state: Arc<DaemonState>) {
    let (reader, mut writer) = tokio::io::split(stream);
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    if reader.read_line(&mut line).await.unwrap_or(0) == 0 {
        return;
    }

    let response = match serde_json::from_str::<serde_json::Value>(&line) {
        Ok(req) => handle_command(req, &state).await,
        Err(e) => serde_json::json!({"ok": false, "error": format!("Parse error: {e}")}),
    };

    let json = serde_json::to_string(&response)
        .unwrap_or_else(|_| r#"{"ok":false,"error":"serialize error"}"#.to_string());
    let _ = writer.write_all(json.as_bytes()).await;
    let _ = writer.write_all(b"\n").await;
}

async fn handle_command(req: serde_json::Value, state: &DaemonState) -> serde_json::Value {
    let cmd = req["cmd"].as_str().unwrap_or("");

    match cmd {
        "ping" => serde_json::json!({"ok": true, "data": "pong"}),

        "status" => {
            let engine = state.engine.read().await;
            let db = state.db.lock().await;
            let stats = db.get_stats().unwrap_or_default();
            let watches = *state.watch_count.read().await;
            serde_json::json!({
                "ok": true,
                "data": {
                    "running": true,
                    "dry_run": state.dry_run,
                    "rules": engine.rules.len(),
                    "watches": watches,
                    "stats": stats,
                }
            })
        }

        "reload" => {
            let rules = state.config.load_all_rules();
            let count = rules.len();
            state.engine.write().await.reload(rules);
            serde_json::json!({"ok": true, "data": {"rules": count}})
        }

        "list_rules" => {
            let rules = state.config.load_all_rules();
            let data: Vec<serde_json::Value> = rules
                .iter()
                .map(|r| {
                    serde_json::json!({
                        "id": r.id,
                        "name": r.name,
                        "enabled": r.enabled,
                        "priority": r.priority,
                        "description": r.description,
                        "folders": r.folders.iter().map(|f| f.path.clone()).collect::<Vec<_>>(),
                    })
                })
                .collect();
            serde_json::json!({"ok": true, "data": data})
        }

        "run_rule" => {
            let rule_id = match req["rule_id"].as_str() {
                Some(id) => id.to_string(),
                None => return serde_json::json!({"ok": false, "error": "rule_id required"}),
            };
            let folder = req["folder"]
                .as_str()
                .map(|f| std::path::PathBuf::from(shellexpand::tilde(f).as_ref()));

            let rules = state.config.load_all_rules();
            let rule = match rules.iter().find(|r| r.id == rule_id) {
                Some(r) => r.clone(),
                None => {
                    return serde_json::json!({"ok": false, "error": format!("Rule {rule_id:?} not found")})
                }
            };

            let folders = resolve_rule_folders(&rule, folder);

            let engine = state.engine.read().await;
            let db = state.db.lock().await;
            let mut count = 0usize;
            let mut skipped = 0usize;

            for folder in &folders {
                let fp = folder.expanded_path();
                if !fp.exists() {
                    continue;
                }
                for p in scan_folder_files(folder) {
                    count += 1;
                    let results = engine.process_file(&p, Some(&fp));
                    for result in &results {
                        if result.skip_reason.is_some() {
                            skipped += 1;
                        }
                        if result.matched && state.config.settings.log_actions {
                            let _ = db.log_result(result);
                        }
                    }
                }
            }

            serde_json::json!({"ok": true, "data": {"files_processed": count, "skipped": skipped}})
        }

        "preview_rule" => {
            let rule_id = match req["rule_id"].as_str() {
                Some(id) => id.to_string(),
                None => return serde_json::json!({"ok": false, "error": "rule_id required"}),
            };
            let folder = req["folder"]
                .as_str()
                .map(|f| PathBuf::from(shellexpand::tilde(f).as_ref()));
            let limit = req["limit"].as_u64().unwrap_or(200) as usize;

            let rules = state.config.load_all_rules();
            let rule = match rules.iter().find(|r| r.id == rule_id) {
                Some(r) => r.clone(),
                None => {
                    return serde_json::json!({"ok": false, "error": format!("Rule {rule_id:?} not found")})
                }
            };

            let preview = build_rule_preview(&rule, folder, limit);
            serde_json::json!({"ok": true, "data": preview})
        }

        "logs" => {
            let limit = req["limit"].as_u64().unwrap_or(50) as usize;
            let rule_id = req["rule_id"].as_str();
            let db = state.db.lock().await;
            match db.get_recent(limit, rule_id) {
                Ok(entries) => serde_json::json!({"ok": true, "data": entries}),
                Err(e) => serde_json::json!({"ok": false, "error": e.to_string()}),
            }
        }

        _ => serde_json::json!({"ok": false, "error": format!("Unknown command: {cmd:?}")}),
    }
}

#[derive(Debug, Serialize)]
struct PreviewData {
    files_scanned: usize,
    matched: Vec<PreviewMatch>,
    skipped: Vec<PreviewSkip>,
    truncated: bool,
}

#[derive(Debug, Serialize)]
struct PreviewMatch {
    path: String,
    rule_id: String,
    rule_name: String,
    dry_run: bool,
    actions: Vec<PreviewAction>,
}

#[derive(Debug, Serialize)]
struct PreviewSkip {
    path: String,
    rule_id: String,
    rule_name: String,
    reason: String,
}

#[derive(Debug, Serialize)]
struct PreviewAction {
    #[serde(rename = "type")]
    action_type: String,
    dry_run: bool,
    success: bool,
    message: String,
    source: Option<String>,
    destination: Option<String>,
    error: String,
}

fn resolve_rule_folders(rule: &RuleConfig, folder: Option<PathBuf>) -> Vec<FolderConfig> {
    if let Some(fp) = folder {
        let matches: Vec<_> = rule
            .folders
            .iter()
            .filter(|f| f.expanded_path() == fp)
            .cloned()
            .collect();
        if matches.is_empty() {
            vec![FolderConfig {
                path: fp.to_string_lossy().to_string(),
                recursive: false,
                depth: 1,
                allow_project_roots: false,
            }]
        } else {
            matches
        }
    } else {
        rule.folders.clone()
    }
}

fn build_rule_preview(rule: &RuleConfig, folder: Option<PathBuf>, limit: usize) -> PreviewData {
    let folders = resolve_rule_folders(rule, folder);
    let mut engine = RuleEngine::new(true);
    engine.load_rules(vec![rule.clone()]);

    let mut preview = PreviewData {
        files_scanned: 0,
        matched: Vec::new(),
        skipped: Vec::new(),
        truncated: false,
    };

    for folder in &folders {
        let fp = folder.expanded_path();
        if !fp.exists() {
            continue;
        }
        for path in scan_folder_files(folder) {
            preview.files_scanned += 1;
            for result in engine.process_file(&path, Some(&fp)) {
                append_preview_result(&mut preview, result, limit);
            }
        }
    }

    preview
}

fn append_preview_result(preview: &mut PreviewData, result: ProcessingResult, limit: usize) {
    if result.skip_reason.is_none() && !result.matched {
        return;
    }

    if preview.matched.len() + preview.skipped.len() >= limit {
        preview.truncated = true;
        return;
    }

    if let Some(reason) = result.skip_reason {
        preview.skipped.push(PreviewSkip {
            path: path_to_string(&result.file_path),
            rule_id: result.rule_id,
            rule_name: result.rule_name,
            reason,
        });
    } else if result.matched {
        preview.matched.push(PreviewMatch {
            path: path_to_string(&result.file_path),
            rule_id: result.rule_id,
            rule_name: result.rule_name,
            dry_run: result.dry_run,
            actions: result
                .action_results
                .into_iter()
                .map(PreviewAction::from)
                .collect(),
        });
    }
}

fn path_to_string(path: &Path) -> String {
    path.to_string_lossy().to_string()
}

impl From<ActionResult> for PreviewAction {
    fn from(result: ActionResult) -> Self {
        Self {
            action_type: result.action_type,
            dry_run: true,
            success: result.success,
            message: result.message,
            source: result.source.as_deref().map(path_to_string),
            destination: result.destination.as_deref().map(path_to_string),
            error: result.error,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::ActionLogger;
    use doumi_core::config::{ConfigManager, Settings};
    use serde_json::json;
    use tempfile::{tempdir, TempDir};
    use tokio::net::UnixStream;
    use tokio::time::{sleep, Duration};

    fn move_rule(root: &Path, dest: &Path, recursive: bool, depth: i32) -> RuleConfig {
        serde_json::from_value(json!({
            "id": "cleanup",
            "name": "Cleanup",
            "enabled": true,
            "priority": 0,
            "folders": [{
                "path": root.to_string_lossy(),
                "recursive": recursive,
                "depth": depth,
                "allow_project_roots": false
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
                "value": ["md", "pdf", "png"]
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

    fn test_config(tmp: &TempDir) -> ConfigManager {
        let config_dir = tmp.path().join("config");
        let rules_dir = config_dir.join("rules");
        let scripts_dir = config_dir.join("scripts");
        let logs_dir = config_dir.join("logs");
        std::fs::create_dir_all(&rules_dir).unwrap();
        std::fs::create_dir_all(&scripts_dir).unwrap();
        std::fs::create_dir_all(&logs_dir).unwrap();

        ConfigManager {
            settings_file: config_dir.join("settings.json"),
            settings: Settings {
                ipc_socket: tmp.path().join("doumi.sock").to_string_lossy().to_string(),
                ..Default::default()
            },
            config_dir,
            rules_dir,
            scripts_dir,
            logs_dir,
        }
    }

    fn state_with_rule(tmp: &TempDir, rule: RuleConfig, dry_run: bool) -> Arc<DaemonState> {
        let config = test_config(tmp);
        let mut saved_rule = rule;
        config.save_rule(&mut saved_rule).unwrap();
        let db = ActionLogger::open(&tmp.path().join("doumi.db")).unwrap();
        DaemonState::new(config, db, dry_run)
    }

    fn unix_socket_bind_available(tmp: &TempDir) -> bool {
        let probe = tmp.path().join("probe.sock");
        match std::os::unix::net::UnixListener::bind(&probe) {
            Ok(listener) => {
                drop(listener);
                let _ = std::fs::remove_file(probe);
                true
            }
            Err(err) if err.kind() == std::io::ErrorKind::PermissionDenied => false,
            Err(err) => panic!("unexpected Unix socket probe error: {err}"),
        }
    }

    async fn socket_request(socket: &Path, request: serde_json::Value) -> serde_json::Value {
        let mut stream = UnixStream::connect(socket).await.unwrap();
        let payload = format!("{}\n", serde_json::to_string(&request).unwrap());
        stream.write_all(payload.as_bytes()).await.unwrap();
        stream.shutdown().await.unwrap();

        let mut reader = BufReader::new(stream);
        let mut line = String::new();
        reader.read_line(&mut line).await.unwrap();
        serde_json::from_str(&line).unwrap()
    }

    async fn wait_for_socket(socket: &Path, server: &tokio::task::JoinHandle<anyhow::Result<()>>) {
        for _ in 0..50 {
            if socket.exists() {
                return;
            }
            assert!(
                !server.is_finished(),
                "IPC server exited before creating socket {}",
                socket.display()
            );
            sleep(Duration::from_millis(10)).await;
        }
        panic!("socket was not created: {}", socket.display());
    }

    #[test]
    fn preview_top_level_match_reports_dry_run_action() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let organized = tmp.path().join("Organized");
        std::fs::create_dir_all(&downloads).unwrap();
        let report = downloads.join("report.pdf");
        std::fs::write(&report, b"pdf").unwrap();

        let rule = move_rule(&downloads, &organized, false, 1);
        let preview = build_rule_preview(&rule, None, 200);

        assert_eq!(preview.files_scanned, 1);
        assert_eq!(preview.matched.len(), 1);
        assert!(preview.skipped.is_empty());
        assert!(!preview.truncated);
        assert_eq!(preview.matched[0].path, path_to_string(&report));
        assert!(preview.matched[0].dry_run);
        assert_eq!(preview.matched[0].actions[0].action_type, "move");
        assert!(preview.matched[0].actions[0].message.contains("[dry-run]"));
        assert!(report.exists());
        assert!(!organized.join("report.pdf").exists());
    }

    #[test]
    fn preview_project_marker_skip_reports_reason() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let config = repo.join(".git").join("config");
        std::fs::write(&config, b"repo config").unwrap();

        let rule = move_rule(&downloads, &tmp.path().join("Organized"), true, 5);
        let preview = build_rule_preview(&rule, None, 200);

        assert_eq!(preview.files_scanned, 1);
        assert!(preview.matched.is_empty());
        assert_eq!(preview.skipped.len(), 1);
        assert_eq!(preview.skipped[0].path, path_to_string(&config));
        assert!(preview.skipped[0].reason.contains("protected project root"));
        assert!(preview.skipped[0].reason.contains(".git"));
        assert!(config.exists());
    }

    #[test]
    fn preview_depth_skip_reports_reason() {
        let tmp = tempdir().unwrap();
        let desktop = tmp.path().join("Desktop");
        let project = desktop.join("Work").join("project");
        std::fs::create_dir_all(&project).unwrap();
        let report = project.join("report.md");
        std::fs::write(&report, b"notes").unwrap();

        let rule = move_rule(&desktop, &tmp.path().join("Organized"), true, 1);
        let preview = build_rule_preview(&rule, None, 200);

        assert_eq!(preview.files_scanned, 1);
        assert!(preview.matched.is_empty());
        assert_eq!(preview.skipped.len(), 1);
        assert_eq!(preview.skipped[0].path, path_to_string(&report));
        assert!(preview.skipped[0]
            .reason
            .contains("outside allowed depth 1"));
        assert!(report.exists());
    }

    #[tokio::test]
    async fn preview_rule_ipc_is_dry_run_even_when_daemon_is_live() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let organized = tmp.path().join("Organized");
        std::fs::create_dir_all(&downloads).unwrap();
        let report = downloads.join("report.pdf");
        std::fs::write(&report, b"pdf").unwrap();

        let rule = move_rule(&downloads, &organized, false, 1);
        let state = state_with_rule(&tmp, rule, false);

        let response =
            handle_command(json!({"cmd": "preview_rule", "rule_id": "cleanup"}), &state).await;

        assert_eq!(response["ok"], true);
        assert_eq!(response["data"]["matched"].as_array().unwrap().len(), 1);
        assert!(response["data"]["matched"][0]["actions"][0]["message"]
            .as_str()
            .unwrap()
            .contains("[dry-run]"));
        assert!(report.exists());
        assert!(!organized.join("report.pdf").exists());
    }

    #[tokio::test]
    async fn run_rule_ipc_response_keeps_existing_count_shape() {
        let tmp = tempdir().unwrap();
        let downloads = tmp.path().join("Downloads");
        let organized = tmp.path().join("Organized");
        std::fs::create_dir_all(&downloads).unwrap();
        let report = downloads.join("report.pdf");
        std::fs::write(&report, b"pdf").unwrap();

        let rule = move_rule(&downloads, &organized, false, 1);
        let state = state_with_rule(&tmp, rule, true);
        let rules = state.config.load_all_rules();
        state.engine.write().await.reload(rules);

        let response =
            handle_command(json!({"cmd": "run_rule", "rule_id": "cleanup"}), &state).await;

        assert_eq!(response["ok"], true);
        assert_eq!(response["data"]["files_processed"], 1);
        assert_eq!(response["data"]["skipped"], 0);
        assert!(response["data"].get("matched").is_none());
        assert!(report.exists());
        assert!(!organized.join("report.pdf").exists());
    }

    #[tokio::test]
    async fn preview_rule_socket_round_trip_reports_match_and_skip() {
        let tmp = tempdir().unwrap();
        if !unix_socket_bind_available(&tmp) {
            eprintln!("skipping socket round-trip: AF_UNIX bind is not permitted");
            return;
        }

        let downloads = tmp.path().join("Downloads");
        let organized = tmp.path().join("Organized");
        let repo = downloads.join("myrepo");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        let report = downloads.join("report.pdf");
        let config = repo.join(".git").join("config");
        std::fs::write(&report, b"pdf").unwrap();
        std::fs::write(&config, b"repo config").unwrap();

        let rule = move_rule(&downloads, &organized, true, 5);
        let state = state_with_rule(&tmp, rule, false);
        let socket = tmp.path().join("preview.sock");
        let server_state = state.clone();
        let server_socket = socket.clone();
        let server = tokio::spawn(async move { run_ipc(&server_socket, server_state).await });
        wait_for_socket(&socket, &server).await;

        let response = socket_request(
            &socket,
            json!({"cmd": "preview_rule", "rule_id": "cleanup", "limit": 200}),
        )
        .await;
        server.abort();

        assert_eq!(response["ok"], true);
        assert_eq!(response["data"]["files_scanned"], 2);
        assert_eq!(response["data"]["matched"].as_array().unwrap().len(), 1);
        assert_eq!(response["data"]["skipped"].as_array().unwrap().len(), 1);
        assert_eq!(
            response["data"]["matched"][0]["actions"][0]["dry_run"],
            true
        );
        assert!(response["data"]["skipped"][0]["reason"]
            .as_str()
            .unwrap()
            .contains("protected project root"));
        assert!(report.exists());
        assert!(config.exists());
        assert!(!organized.join("report.pdf").exists());
    }
}
