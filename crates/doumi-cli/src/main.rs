use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process;

use clap::{Parser, Subcommand};
use serde_json::Value;

use doumi_core::config::ConfigManager;
use doumi_core::loader::{load_rule_file, save_rule_file};
use doumi_core::rule::FolderConfig;
use doumi_core::scope::scan_folder_files;

// ─── IPC helper ──────────────────────────────────────────────────────────────

fn ipc_call(socket: &Path, cmd: Value) -> Value {
    use std::io::{BufRead, BufReader};
    use std::net::Shutdown;
    use std::os::unix::net::UnixStream;

    let Ok(mut stream) = UnixStream::connect(socket) else {
        return serde_json::json!({"ok": false, "error": "Daemon not running (socket not found)"});
    };
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(5)))
        .ok();

    let _ = stream.write_all(serde_json::to_string(&cmd).unwrap().as_bytes());
    let _ = stream.write_all(b"\n");
    let _ = stream.shutdown(Shutdown::Write);

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    if reader.read_line(&mut line).unwrap_or(0) == 0 {
        return serde_json::json!({"ok": false, "error": "No response from daemon"});
    }
    serde_json::from_str(&line)
        .unwrap_or_else(|_| serde_json::json!({"ok": false, "error": "Invalid response"}))
}

fn get_config() -> ConfigManager {
    ConfigManager::new().unwrap_or_else(|e| {
        eprintln!("Config error: {e}");
        process::exit(1);
    })
}

fn daemon_call(cmd: Value) -> Value {
    let cfg = get_config();
    ipc_call(&cfg.ipc_socket_path(), cmd)
}

// ─── CLI definitions ─────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(
    name = "doumi",
    about = "Doumi — intelligent file organizer for Linux & BSD",
    version
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Manage the background daemon
    Daemon {
        #[command(subcommand)]
        sub: DaemonCmd,
    },
    /// Manage file organization rules
    Rules {
        #[command(subcommand)]
        sub: RulesCmd,
    },
    /// View recent action log
    Logs {
        #[arg(short = 'n', long, default_value = "50")]
        limit: usize,
        #[arg(short, long)]
        rule: Option<String>,
        #[arg(long)]
        json: bool,
    },
    /// View and edit settings
    Config {
        #[command(subcommand)]
        sub: ConfigCmd,
    },
    /// Launch the graphical interface
    Gui,
}

#[derive(Subcommand)]
enum DaemonCmd {
    /// Start the daemon
    Start {
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        debug: bool,
    },
    /// Stop the daemon
    Stop,
    /// Show daemon status
    Status,
    /// Reload rules without restart
    Reload,
}

#[derive(Subcommand)]
enum RulesCmd {
    /// List all rules
    List {
        #[arg(long)]
        json: bool,
    },
    /// Show full rule JSON
    Show { rule_id: String },
    /// Create a new rule scaffold
    Add {
        name: String,
        #[arg(short, long, required = true)]
        folder: Vec<String>,
        #[arg(long, default_value = "true")]
        on_add: bool,
        #[arg(long)]
        schedule: Option<String>,
        #[arg(long)]
        edit: bool,
    },
    /// Open rule in $EDITOR
    Edit { rule_id: String },
    /// Delete a rule
    Delete { rule_id: String },
    /// Enable a rule
    Enable { rule_id: String },
    /// Disable a rule
    Disable { rule_id: String },
    /// Run a rule manually against its folders
    Run {
        rule_id: String,
        #[arg(short, long)]
        folder: Option<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Preview a rule through the daemon without changing files
    Preview {
        rule_id: String,
        #[arg(short, long)]
        folder: Option<String>,
        #[arg(long, default_value = "200")]
        limit: usize,
        #[arg(long)]
        json: bool,
    },
    /// Import a rule from a JSON file
    Import { path: PathBuf },
    /// Export a rule to a JSON file
    Export { rule_id: String, output: PathBuf },
}

#[derive(Subcommand)]
enum ConfigCmd {
    /// Show current settings
    Show,
    /// Set a config key
    Set { key: String, value: String },
    /// Print config directory path
    Dir,
}

// ─── Main ────────────────────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Commands::Daemon { sub } => handle_daemon(sub),
        Commands::Rules { sub } => handle_rules(sub),
        Commands::Logs { limit, rule, json } => handle_logs(limit, rule.as_deref(), json),
        Commands::Config { sub } => handle_config(sub),
        Commands::Gui => handle_gui(),
    }
}

// ─── Daemon commands ──────────────────────────────────────────────────────────

fn handle_daemon(cmd: DaemonCmd) {
    match cmd {
        DaemonCmd::Start { dry_run, debug } => {
            let cfg = get_config();
            let resp = ipc_call(&cfg.ipc_socket_path(), serde_json::json!({"cmd": "ping"}));
            if resp["ok"].as_bool().unwrap_or(false) {
                println!("Daemon already running");
                return;
            }

            let doumid = find_binary("doumid");
            let mut child = std::process::Command::new(&doumid);
            if dry_run {
                child.arg("--dry-run");
            }
            if debug {
                child.arg("--debug");
            }
            child
                .stdout(process::Stdio::null())
                .stderr(process::Stdio::null());

            #[cfg(unix)]
            unsafe {
                use std::os::unix::process::CommandExt;
                child.pre_exec(|| {
                    libc::setsid();
                    Ok(())
                });
            }

            match child.spawn() {
                Ok(_) => println!("Daemon started"),
                Err(e) => {
                    eprintln!("Failed to start daemon: {e}");
                    process::exit(1);
                }
            }
        }

        DaemonCmd::Stop => {
            let cfg = get_config();
            let sock = cfg.ipc_socket_path();
            if !sock.exists() {
                eprintln!("Daemon not running");
                return;
            }
            let pid_file = sock.with_extension("pid");
            if let Ok(pid_str) = std::fs::read_to_string(&pid_file) {
                if let Ok(pid) = pid_str.trim().parse::<u32>() {
                    #[cfg(unix)]
                    unsafe {
                        libc::kill(pid as i32, libc::SIGTERM);
                    }
                    println!("Sent SIGTERM to pid {pid}");
                    return;
                }
            }
            // Fallback
            let _ = std::process::Command::new("pkill")
                .arg("-f")
                .arg("doumid")
                .status();
            println!("Daemon stopped");
        }

        DaemonCmd::Status => {
            let resp = daemon_call(serde_json::json!({"cmd": "status"}));
            if !resp["ok"].as_bool().unwrap_or(false) {
                println!(
                    "Daemon offline: {}",
                    resp["error"].as_str().unwrap_or("unknown")
                );
                return;
            }
            let d = &resp["data"];
            println!("Status:          Running");
            println!(
                "Mode:            {}",
                if d["dry_run"].as_bool().unwrap_or(false) {
                    "dry-run"
                } else {
                    "live"
                }
            );
            println!("Rules:           {}", d["rules"]);
            println!("Watched folders: {}", d["watches"]);
            let stats = &d["stats"];
            println!("Total events:    {}", stats["total_events"]);
            println!("Actions OK:      {}", stats["actions_ok"]);
            println!("Actions failed:  {}", stats["actions_failed"]);
        }

        DaemonCmd::Reload => {
            let resp = daemon_call(serde_json::json!({"cmd": "reload"}));
            if resp["ok"].as_bool().unwrap_or(false) {
                println!("Reloaded {} rules", resp["data"]["rules"]);
            } else {
                eprintln!("Error: {}", resp["error"].as_str().unwrap_or("unknown"));
                process::exit(1);
            }
        }
    }
}

// ─── Rules commands ───────────────────────────────────────────────────────────

fn handle_rules(cmd: RulesCmd) {
    match cmd {
        RulesCmd::List { json } => {
            let cfg = get_config();
            let rules = cfg.load_all_rules();
            if json {
                println!("{}", serde_json::to_string_pretty(&rules).unwrap());
                return;
            }
            if rules.is_empty() {
                println!("No rules configured. Add one with: doumi rules add <name> -f <folder>");
                return;
            }
            println!(
                "{:<12} {:<30} {:<10} {:>4}  {}",
                "ID", "Name", "Status", "Pri", "Triggers"
            );
            println!("{}", "-".repeat(70));
            for r in &rules {
                let status = if r.enabled { "enabled" } else { "disabled" };
                let mut triggers = vec![];
                if r.triggers.on_add {
                    triggers.push("add");
                }
                if r.triggers.on_modify {
                    triggers.push("modify");
                }
                if r.triggers.schedule.is_some() {
                    triggers.push("cron");
                }
                println!(
                    "{:<12} {:<30} {:<10} {:>4}  {}",
                    &r.id[..r.id.len().min(12)],
                    &r.name[..r.name.len().min(30)],
                    status,
                    r.priority,
                    triggers.join(", ")
                );
            }
        }

        RulesCmd::Show { rule_id } => {
            let cfg = get_config();
            let Some(rule) = cfg.get_rule_by_id(&rule_id) else {
                eprintln!("Rule {rule_id:?} not found");
                process::exit(1);
            };
            println!("{}", serde_json::to_string_pretty(&rule).unwrap());
        }

        RulesCmd::Add {
            name,
            folder,
            on_add,
            schedule,
            edit,
        } => {
            let cfg = get_config();
            let rule_id = &uuid::Uuid::new_v4().to_string()[..8];

            let raw = serde_json::json!({
                "id": rule_id,
                "name": name,
                "enabled": true,
                "priority": 0,
                "description": "",
                "folders": folder.iter().map(|f| serde_json::json!({
                    "path": PathBuf::from(f).to_string_lossy(),
                    "recursive": false
                })).collect::<Vec<_>>(),
                "triggers": {
                    "on_add": on_add,
                    "on_modify": false,
                    "on_delete": false,
                    "schedule": schedule
                },
                "conditions": {
                    "type": "group",
                    "match": "all",
                    "items": [
                        {"type": "extension", "operator": "is_one_of", "value": ["pdf", "jpg", "png"]}
                    ]
                },
                "actions": [
                    {"type": "move", "destination": "~/Organized/{kind}/{year}", "on_conflict": "rename"}
                ],
                "continue_matching": true
            });

            let mut rule: doumi_core::rule::RuleConfig = serde_json::from_value(raw).unwrap();
            let path = cfg.save_rule(&mut rule).unwrap();
            println!("Created rule {rule_id} → {}", path.display());

            if edit {
                let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
                let _ = std::process::Command::new(editor).arg(&path).status();
            }
        }

        RulesCmd::Edit { rule_id } => {
            let cfg = get_config();
            let Some(rule) = cfg.get_rule_by_id(&rule_id) else {
                eprintln!("Rule {rule_id:?} not found");
                process::exit(1);
            };
            let src = rule
                .source_file
                .unwrap_or_else(|| cfg.rules_dir.join(format!("{rule_id}.json")));
            let editor = std::env::var("EDITOR").unwrap_or_else(|_| "nano".to_string());
            let _ = std::process::Command::new(editor).arg(&src).status();
            println!("Tip: run 'doumi daemon reload' to apply changes");
        }

        RulesCmd::Delete { rule_id } => {
            print!("Delete rule {rule_id}? [y/N] ");
            std::io::stdout().flush().ok();
            let mut ans = String::new();
            std::io::stdin().read_line(&mut ans).ok();
            if !ans.trim().eq_ignore_ascii_case("y") {
                println!("Aborted");
                return;
            }
            let cfg = get_config();
            if cfg.delete_rule(&rule_id) {
                println!("Deleted rule {rule_id}");
            } else {
                eprintln!("Rule {rule_id:?} not found");
                process::exit(1);
            }
        }

        RulesCmd::Enable { rule_id } => toggle_rule(&rule_id, true),
        RulesCmd::Disable { rule_id } => toggle_rule(&rule_id, false),

        RulesCmd::Run {
            rule_id,
            folder,
            dry_run,
        } => {
            let cfg = get_config();
            let Some(rule) = cfg.get_rule_by_id(&rule_id) else {
                eprintln!("Rule {rule_id:?} not found");
                process::exit(1);
            };

            let mut engine = doumi_core::engine::RuleEngine::new(dry_run);
            engine.load_rules(vec![rule.clone()]);

            let folders: Vec<FolderConfig> = if let Some(f) = folder {
                let fp = PathBuf::from(shellexpand::tilde(&f).as_ref());
                let matches: Vec<_> = rule
                    .folders
                    .iter()
                    .filter(|folder| folder.expanded_path() == fp)
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
            };

            let mut total = 0usize;
            let mut matched = 0usize;
            let mut skipped = 0usize;

            for folder in &folders {
                let fp = folder.expanded_path();
                if !fp.exists() {
                    eprintln!("Folder {} does not exist", fp.display());
                    continue;
                }
                for path in scan_folder_files(folder) {
                    total += 1;
                    let results = engine.process_file(&path, Some(&fp));
                    for result in &results {
                        if let Some(reason) = &result.skip_reason {
                            skipped += 1;
                            if dry_run {
                                println!(
                                    "[dry] {}: skipped {} ({reason})",
                                    result.rule_name,
                                    path.file_name().unwrap_or_default().to_string_lossy()
                                );
                            }
                        } else if result.matched {
                            matched += 1;
                            let prefix = if dry_run { "[dry] " } else { "" };
                            println!(
                                "{prefix}{}: matched {}",
                                result.rule_name,
                                path.file_name().unwrap_or_default().to_string_lossy()
                            );
                            for ar in &result.action_results {
                                let icon = if ar.success { '✓' } else { '✗' };
                                println!(
                                    "  {icon} {}: {}",
                                    ar.action_type,
                                    if ar.success { &ar.message } else { &ar.error }
                                );
                            }
                        }
                    }
                }
            }
            if dry_run {
                println!(
                    "\nScanned {total} files — {matched} matched, {skipped} skipped by safety"
                );
            } else {
                println!("\nScanned {total} files — {matched} matched");
            }
        }

        RulesCmd::Preview {
            rule_id,
            folder,
            limit,
            json,
        } => {
            let resp = daemon_call(serde_json::json!({
                "cmd": "preview_rule",
                "rule_id": rule_id,
                "folder": folder,
                "limit": limit,
            }));
            if !resp["ok"].as_bool().unwrap_or(false) {
                eprintln!(
                    "Preview error: {}",
                    resp["error"].as_str().unwrap_or("unknown")
                );
                process::exit(1);
            }

            let data = &resp["data"];
            if json {
                println!("{}", serde_json::to_string_pretty(data).unwrap());
            } else {
                print_preview(data);
            }
        }

        RulesCmd::Import { path } => {
            let cfg = get_config();
            match load_rule_file(&path) {
                Ok(mut rule) => {
                    let saved = cfg.save_rule(&mut rule).unwrap();
                    println!("Imported {:?} → {}", rule.name, saved.display());
                }
                Err(e) => {
                    eprintln!("Import failed: {e}");
                    process::exit(1);
                }
            }
        }

        RulesCmd::Export { rule_id, output } => {
            let cfg = get_config();
            let Some(rule) = cfg.get_rule_by_id(&rule_id) else {
                eprintln!("Rule {rule_id:?} not found");
                process::exit(1);
            };
            save_rule_file(&rule, &output).unwrap();
            println!("Exported {:?} → {}", rule.name, output.display());
        }
    }
}

fn print_preview(data: &Value) {
    let files_scanned = data["files_scanned"].as_u64().unwrap_or(0);
    let matched = data["matched"].as_array().cloned().unwrap_or_default();
    let skipped = data["skipped"].as_array().cloned().unwrap_or_default();
    let truncated = data["truncated"].as_bool().unwrap_or(false);

    println!(
        "Preview scanned {files_scanned} files - {} matched, {} skipped",
        matched.len(),
        skipped.len()
    );
    if truncated {
        println!("Result truncated by limit");
    }

    if !matched.is_empty() {
        println!("\nMatched");
        for item in &matched {
            let path = item["path"].as_str().unwrap_or("?");
            let rule_name = item["rule_name"].as_str().unwrap_or("?");
            println!("  {rule_name}: {path}");
            if let Some(actions) = item["actions"].as_array() {
                for action in actions {
                    let atype = action["type"].as_str().unwrap_or("?");
                    let msg = action["message"]
                        .as_str()
                        .or_else(|| action["error"].as_str())
                        .unwrap_or("");
                    println!("    [dry] {atype}: {msg}");
                }
            }
        }
    }

    if !skipped.is_empty() {
        println!("\nSkipped by safety");
        for item in &skipped {
            let path = item["path"].as_str().unwrap_or("?");
            let reason = item["reason"].as_str().unwrap_or("?");
            println!("  {path}");
            println!("    {reason}");
        }
    }
}

fn toggle_rule(rule_id: &str, enabled: bool) {
    let cfg = get_config();
    let Some(mut rule) = cfg.get_rule_by_id(rule_id) else {
        eprintln!("Rule {rule_id:?} not found");
        process::exit(1);
    };
    rule.enabled = enabled;
    cfg.save_rule(&mut rule).unwrap();
    println!(
        "Rule {:?} {}",
        rule.name,
        if enabled { "enabled" } else { "disabled" }
    );
}

// ─── Logs ─────────────────────────────────────────────────────────────────────

fn handle_logs(limit: usize, rule: Option<&str>, json: bool) {
    let resp = daemon_call(serde_json::json!({
        "cmd": "logs",
        "limit": limit,
        "rule_id": rule,
    }));

    let entries = if resp["ok"].as_bool().unwrap_or(false) {
        resp["data"].clone()
    } else {
        // Fallback: read DB directly
        let cfg = get_config();
        match crate_db_fallback(&cfg, limit, rule) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("Logs error: {e}");
                return;
            }
        }
    };

    let arr = match entries.as_array() {
        Some(a) => a.clone(),
        None => {
            println!("No log entries");
            return;
        }
    };

    if json {
        println!("{}", serde_json::to_string_pretty(&arr).unwrap());
        return;
    }

    if arr.is_empty() {
        println!("No log entries");
        return;
    }

    for entry in &arr {
        let ts = entry["ts"]
            .as_str()
            .unwrap_or("?")
            .get(..19)
            .unwrap_or("?")
            .replace('T', " ");
        let name = entry["rule_name"].as_str().unwrap_or("?");
        let fpath = std::path::Path::new(entry["file_path"].as_str().unwrap_or("?"))
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let dry = if entry["dry_run"].as_bool().unwrap_or(false) {
            " [dry]"
        } else {
            ""
        };
        println!("{ts}{dry}  {name} → {fpath}");
        if let Some(actions) = entry["actions"].as_array() {
            for action in actions {
                let ok = action["success"].as_bool().unwrap_or(false);
                let icon = if ok { '✓' } else { '✗' };
                let atype = action["action_type"].as_str().unwrap_or("?");
                let msg = action["message"]
                    .as_str()
                    .or_else(|| action["error"].as_str())
                    .unwrap_or("");
                println!("  {icon} {atype}: {msg}");
            }
        }
    }
}

fn crate_db_fallback(
    cfg: &ConfigManager,
    limit: usize,
    rule: Option<&str>,
) -> anyhow::Result<Value> {
    use rusqlite::{params, Connection};
    let conn = Connection::open(cfg.db_path())?;
    let rows: Vec<Value> = if let Some(rid) = rule {
        conn.prepare("SELECT id,ts,rule_id,rule_name,file_path,matched,dry_run FROM events WHERE rule_id=?1 ORDER BY ts DESC LIMIT ?2")?
            .query_map(params![rid, limit as i64], |r| Ok(serde_json::json!({
                "id": r.get::<_,i64>(0)?,
                "ts": r.get::<_,String>(1)?,
                "rule_id": r.get::<_,String>(2)?,
                "rule_name": r.get::<_,String>(3)?,
                "file_path": r.get::<_,String>(4)?,
                "matched": r.get::<_,i64>(5)? != 0,
                "dry_run": r.get::<_,i64>(6)? != 0,
                "actions": [],
            })))?
            .collect::<Result<Vec<_>,_>>()?
    } else {
        conn.prepare("SELECT id,ts,rule_id,rule_name,file_path,matched,dry_run FROM events ORDER BY ts DESC LIMIT ?1")?
            .query_map(params![limit as i64], |r| Ok(serde_json::json!({
                "id": r.get::<_,i64>(0)?,
                "ts": r.get::<_,String>(1)?,
                "rule_id": r.get::<_,String>(2)?,
                "rule_name": r.get::<_,String>(3)?,
                "file_path": r.get::<_,String>(4)?,
                "matched": r.get::<_,i64>(5)? != 0,
                "dry_run": r.get::<_,i64>(6)? != 0,
                "actions": [],
            })))?
            .collect::<Result<Vec<_>,_>>()?
    };
    Ok(Value::Array(rows))
}

// ─── Config commands ─────────────────────────────────────────────────────────

fn handle_config(cmd: ConfigCmd) {
    match cmd {
        ConfigCmd::Show => {
            let cfg = get_config();
            println!("{}", serde_json::to_string_pretty(&cfg.settings).unwrap());
        }
        ConfigCmd::Set { key, value } => {
            let mut cfg = get_config();
            let parsed: Value = if value.eq_ignore_ascii_case("true") {
                Value::Bool(true)
            } else if value.eq_ignore_ascii_case("false") {
                Value::Bool(false)
            } else if let Ok(n) = value.parse::<i64>() {
                Value::Number(n.into())
            } else {
                Value::String(value.clone())
            };
            cfg.set_setting(&key, parsed).unwrap();
            println!("Set {key} = {value}");
        }
        ConfigCmd::Dir => {
            let cfg = get_config();
            println!("{}", cfg.config_dir.display());
        }
    }
}

// ─── GUI launcher ────────────────────────────────────────────────────────────

fn handle_gui() {
    let doumi_gui = find_binary("doumi-gui");
    match std::process::Command::new(&doumi_gui).spawn() {
        Ok(_) => {}
        Err(e) => {
            eprintln!("GUI unavailable: {e}");
            process::exit(1);
        }
    }
}

// ─── Utilities ───────────────────────────────────────────────────────────────

fn find_binary(name: &str) -> PathBuf {
    // Look next to current binary first
    if let Ok(exe) = std::env::current_exe() {
        let sibling = exe.parent().unwrap_or(Path::new(".")).join(name);
        if sibling.exists() {
            return sibling;
        }
    }
    PathBuf::from(name)
}
