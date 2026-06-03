use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::io::Write as IoWrite;
use std::path::{Path, PathBuf};

use crate::models::{ActionResult, FileInfo};
use crate::template::{render_template, resolve_destination, unique_path};

// ─── ConflictPolicy ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub enum ConflictPolicy {
    #[default]
    Rename,
    Skip,
    Overwrite,
}

impl<'de> Deserialize<'de> for ConflictPolicy {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "rename" => ConflictPolicy::Rename,
            "skip" => ConflictPolicy::Skip,
            "overwrite" => ConflictPolicy::Overwrite,
            _ => ConflictPolicy::Rename,
        })
    }
}

impl Serialize for ConflictPolicy {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            ConflictPolicy::Rename => "rename",
            ConflictPolicy::Skip => "skip",
            ConflictPolicy::Overwrite => "overwrite",
        })
    }
}

// ─── ArchiveFormat ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Default)]
pub enum ArchiveFormat {
    #[default]
    Zip,
    TarGz,
    TarBz2,
    Tar,
}

impl<'de> Deserialize<'de> for ArchiveFormat {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "zip" => ArchiveFormat::Zip,
            "tar.gz" => ArchiveFormat::TarGz,
            "tar.bz2" => ArchiveFormat::TarBz2,
            "tar" => ArchiveFormat::Tar,
            _ => ArchiveFormat::Zip,
        })
    }
}

impl Serialize for ArchiveFormat {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            ArchiveFormat::Zip => "zip",
            ArchiveFormat::TarGz => "tar.gz",
            ArchiveFormat::TarBz2 => "tar.bz2",
            ArchiveFormat::Tar => "tar",
        })
    }
}

impl ArchiveFormat {
    pub fn extension(&self) -> &str {
        match self {
            ArchiveFormat::Zip => "zip",
            ArchiveFormat::TarGz => "tar.gz",
            ArchiveFormat::TarBz2 => "tar.bz2",
            ArchiveFormat::Tar => "tar",
        }
    }
}

// ─── Action enum ─────────────────────────────────────────────────────────────

fn default_true() -> bool {
    true
}
fn default_title() -> String {
    "Doumi".to_string()
}
fn default_bash() -> String {
    "bash".to_string()
}
fn default_conflict() -> ConflictPolicy {
    ConflictPolicy::Rename
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Action {
    Move {
        destination: String,
        #[serde(default = "default_conflict")]
        on_conflict: ConflictPolicy,
        #[serde(default = "default_true")]
        create_parents: bool,
    },
    Copy {
        destination: String,
        #[serde(default = "default_conflict")]
        on_conflict: ConflictPolicy,
        #[serde(default = "default_true")]
        create_parents: bool,
    },
    Delete {
        #[serde(default)]
        recursive: bool,
    },
    Trash {},
    Rename {
        pattern: String,
        #[serde(default = "default_conflict")]
        on_conflict: ConflictPolicy,
    },
    #[serde(alias = "script")]
    RunScript {
        command: String,
        #[serde(default)]
        args: Vec<String>,
        #[serde(default = "default_bash")]
        interpreter: String,
    },
    #[serde(alias = "notification")]
    Notify {
        #[serde(default = "default_title")]
        title: String,
        #[serde(default)]
        body: String,
    },
    #[serde(alias = "archive")]
    Compress {
        #[serde(default)]
        destination: Option<String>,
        #[serde(default)]
        format: ArchiveFormat,
        #[serde(default = "default_true")]
        create_parents: bool,
    },
    #[serde(alias = "chmod")]
    SetPermissions {
        permissions: String,
    },
    Tag {
        tags: Vec<String>,
    },
    Log {
        #[serde(default)]
        message: String,
        #[serde(default)]
        destination: Option<String>,
    },
    Open {
        #[serde(default)]
        command: Option<String>,
    },
    #[serde(alias = "mkdir")]
    CreateFolder {
        destination: String,
    },
}

// ─── Execution ───────────────────────────────────────────────────────────────

impl Action {
    pub fn execute(&self, file: &FileInfo, dry_run: bool) -> ActionResult {
        match self {
            Action::Move {
                destination,
                on_conflict,
                create_parents,
            } => execute_move(file, destination, on_conflict, *create_parents, dry_run),
            Action::Copy {
                destination,
                on_conflict,
                create_parents,
            } => execute_copy(file, destination, on_conflict, *create_parents, dry_run),
            Action::Delete { recursive: _ } => execute_delete(file, dry_run),
            Action::Trash {} => execute_trash(file, dry_run),
            Action::Rename {
                pattern,
                on_conflict,
            } => execute_rename(file, pattern, on_conflict, dry_run),
            Action::RunScript {
                command,
                args,
                interpreter,
            } => execute_run_script(file, command, args, interpreter, dry_run),
            Action::Notify { title, body } => execute_notify(file, title, body, dry_run),
            Action::Compress {
                destination,
                format,
                create_parents,
            } => execute_compress(
                file,
                destination.as_deref(),
                format,
                *create_parents,
                dry_run,
            ),
            Action::SetPermissions { permissions } => {
                execute_set_permissions(file, permissions, dry_run)
            }
            Action::Tag { tags } => execute_tag(file, tags, dry_run),
            Action::Log {
                message,
                destination,
            } => execute_log(file, message, destination.as_deref(), dry_run),
            Action::Open { command } => execute_open(file, command.as_deref(), dry_run),
            Action::CreateFolder { destination } => {
                execute_create_folder(file, destination, dry_run)
            }
        }
    }
}

// ─── Action implementations ──────────────────────────────────────────────────

fn apply_conflict(dest: PathBuf, policy: &ConflictPolicy) -> Result<Option<PathBuf>, ActionResult> {
    if !dest.exists() {
        return Ok(Some(dest));
    }
    match policy {
        ConflictPolicy::Skip => Err(ActionResult {
            action_type: String::new(),
            success: true,
            message: format!("Skipped (exists): {}", dest.display()),
            source: None,
            destination: Some(dest),
            error: String::new(),
        }),
        ConflictPolicy::Overwrite => Ok(Some(dest)),
        ConflictPolicy::Rename => Ok(Some(unique_path(dest))),
    }
}

fn execute_move(
    file: &FileInfo,
    destination: &str,
    on_conflict: &ConflictPolicy,
    create_parents: bool,
    dry_run: bool,
) -> ActionResult {
    let src = file.path.clone();
    let dest_dir = resolve_destination(destination, file);
    let dest = if destination.ends_with('/') || dest_dir.extension().is_none() {
        dest_dir.join(&file.name)
    } else {
        dest_dir
    };

    let dest = match apply_conflict(dest, on_conflict) {
        Ok(Some(d)) => d,
        Ok(None) => unreachable!(),
        Err(mut r) => {
            r.action_type = "move".to_string();
            r.source = Some(src);
            return r;
        }
    };

    if dry_run {
        return ActionResult {
            action_type: "move".to_string(),
            success: true,
            message: format!("[dry-run] {} → {}", src.display(), dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        };
    }

    if create_parents {
        if let Some(p) = dest.parent() {
            if let Err(e) = std::fs::create_dir_all(p) {
                return ActionResult::failure("move", e.to_string()).with_paths(src, dest);
            }
        }
    }

    match std::fs::rename(&src, &dest) {
        Ok(()) => ActionResult {
            action_type: "move".to_string(),
            success: true,
            message: format!("Moved → {}", dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        },
        Err(e) if e.raw_os_error() == Some(18) => {
            // EXDEV: cross-device move — copy then delete
            match copy_path(&src, &dest) {
                Ok(()) => {
                    let _ = remove_path(&src);
                    ActionResult {
                        action_type: "move".to_string(),
                        success: true,
                        message: format!("Moved (cross-device) → {}", dest.display()),
                        source: Some(src),
                        destination: Some(dest),
                        error: String::new(),
                    }
                }
                Err(e2) => ActionResult::failure("move", e2.to_string()).with_paths(src, dest),
            }
        }
        Err(e) => ActionResult::failure("move", e.to_string()).with_paths(src, dest),
    }
}

fn execute_copy(
    file: &FileInfo,
    destination: &str,
    on_conflict: &ConflictPolicy,
    create_parents: bool,
    dry_run: bool,
) -> ActionResult {
    let src = file.path.clone();
    let dest_dir = resolve_destination(destination, file);
    let dest = if dest_dir.extension().is_none() {
        dest_dir.join(&file.name)
    } else {
        dest_dir
    };

    let dest = match apply_conflict(dest, on_conflict) {
        Ok(Some(d)) => d,
        Ok(None) => unreachable!(),
        Err(mut r) => {
            r.action_type = "copy".to_string();
            r.source = Some(src);
            return r;
        }
    };

    if dry_run {
        return ActionResult {
            action_type: "copy".to_string(),
            success: true,
            message: format!("[dry-run] {} → {}", src.display(), dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        };
    }

    if create_parents {
        if let Some(p) = dest.parent() {
            if let Err(e) = std::fs::create_dir_all(p) {
                return ActionResult::failure("copy", e.to_string()).with_paths(src, dest);
            }
        }
    }

    match copy_path(&src, &dest) {
        Ok(()) => ActionResult {
            action_type: "copy".to_string(),
            success: true,
            message: format!("Copied → {}", dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        },
        Err(e) => ActionResult::failure("copy", e.to_string()).with_paths(src, dest),
    }
}

fn execute_delete(file: &FileInfo, dry_run: bool) -> ActionResult {
    let p = file.path.clone();
    if dry_run {
        return ActionResult::success("delete", format!("[dry-run] delete {}", p.display()));
    }
    match remove_path(&p) {
        Ok(()) => ActionResult::success("delete", format!("Deleted {}", p.display())),
        Err(e) => ActionResult::failure("delete", e.to_string()),
    }
}

fn execute_trash(file: &FileInfo, dry_run: bool) -> ActionResult {
    let p = file.path.clone();
    if dry_run {
        return ActionResult::success("trash", format!("[dry-run] trash {}", p.display()));
    }
    match trash::delete(&p) {
        Ok(()) => ActionResult::success("trash", format!("Trashed {}", p.display())),
        Err(e) => ActionResult::failure("trash", e.to_string()),
    }
}

fn execute_rename(
    file: &FileInfo,
    pattern: &str,
    on_conflict: &ConflictPolicy,
    dry_run: bool,
) -> ActionResult {
    let src = file.path.clone();
    let new_name = render_template(pattern, file);
    let dest = src.parent().unwrap_or(Path::new(".")).join(&new_name);

    let dest = if dest.exists() && dest != src {
        match apply_conflict(dest, on_conflict) {
            Ok(Some(d)) => d,
            Ok(None) => unreachable!(),
            Err(mut r) => {
                r.action_type = "rename".to_string();
                r.source = Some(src);
                return r;
            }
        }
    } else {
        dest
    };

    if dry_run {
        return ActionResult {
            action_type: "rename".to_string(),
            success: true,
            message: format!(
                "[dry-run] {} → {}",
                src.file_name().unwrap_or_default().to_string_lossy(),
                dest.file_name().unwrap_or_default().to_string_lossy()
            ),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        };
    }

    match std::fs::rename(&src, &dest) {
        Ok(()) => ActionResult {
            action_type: "rename".to_string(),
            success: true,
            message: format!(
                "Renamed → {}",
                dest.file_name().unwrap_or_default().to_string_lossy()
            ),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        },
        Err(e) => ActionResult::failure("rename", e.to_string()).with_paths(src, dest),
    }
}

fn execute_run_script(
    file: &FileInfo,
    command: &str,
    args: &[String],
    interpreter: &str,
    dry_run: bool,
) -> ActionResult {
    let cmd = shellexpand::tilde(command).to_string();
    let rendered_args: Vec<String> = if args.is_empty() {
        vec![file.path.to_string_lossy().to_string()]
    } else {
        args.iter().map(|a| render_template(a, file)).collect()
    };

    if dry_run {
        return ActionResult::success(
            "run_script",
            format!("[dry-run] {} {}", cmd, rendered_args.join(" ")),
        );
    }

    match std::process::Command::new(interpreter)
        .arg(&cmd)
        .args(&rendered_args)
        .output()
    {
        Ok(out) => {
            let success = out.status.success();
            let msg = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
            ActionResult {
                action_type: "run_script".to_string(),
                success,
                message: if msg.is_empty() {
                    format!("exit {}", out.status.code().unwrap_or(-1))
                } else {
                    msg
                },
                source: Some(file.path.clone()),
                destination: None,
                error: if success { String::new() } else { err },
            }
        }
        Err(e) => ActionResult::failure("run_script", e.to_string()),
    }
}

fn execute_notify(file: &FileInfo, title: &str, body: &str, dry_run: bool) -> ActionResult {
    let title = render_template(title, file);
    let body = if body.is_empty() {
        format!("{} processed", file.name)
    } else {
        render_template(body, file)
    };

    if dry_run {
        return ActionResult::success("notify", format!("[dry-run] {title}: {body}"));
    }

    match notify_rust::Notification::new()
        .summary(&title)
        .body(&body)
        .show()
    {
        Ok(_) => ActionResult::success("notify", format!("Notified: {title}")),
        Err(e) => ActionResult::failure("notify", e.to_string()),
    }
}

fn execute_compress(
    file: &FileInfo,
    destination: Option<&str>,
    format: &ArchiveFormat,
    create_parents: bool,
    dry_run: bool,
) -> ActionResult {
    let src = file.path.clone();
    let dest = if let Some(tpl) = destination {
        resolve_destination(tpl, file)
    } else {
        src.parent()
            .unwrap_or(Path::new("."))
            .join(format!("{}.{}", file.stem, format.extension()))
    };

    if dry_run {
        return ActionResult {
            action_type: "compress".to_string(),
            success: true,
            message: format!("[dry-run] compress → {}", dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        };
    }

    if create_parents {
        if let Some(p) = dest.parent() {
            if let Err(e) = std::fs::create_dir_all(p) {
                return ActionResult::failure("compress", e.to_string());
            }
        }
    }

    let result = match format {
        ArchiveFormat::Zip => compress_zip(&src, &dest),
        ArchiveFormat::TarGz => compress_tar_gz(&src, &dest),
        ArchiveFormat::TarBz2 => compress_tar_bz2(&src, &dest),
        ArchiveFormat::Tar => compress_tar(&src, &dest),
    };

    match result {
        Ok(()) => ActionResult {
            action_type: "compress".to_string(),
            success: true,
            message: format!("Compressed → {}", dest.display()),
            source: Some(src),
            destination: Some(dest),
            error: String::new(),
        },
        Err(e) => ActionResult::failure("compress", e.to_string()).with_paths(src, dest),
    }
}

fn execute_set_permissions(file: &FileInfo, permissions: &str, dry_run: bool) -> ActionResult {
    let p = &file.path;
    let mode = u32::from_str_radix(permissions.trim_start_matches("0o"), 8)
        .unwrap_or_else(|_| u32::from_str_radix(permissions, 8).unwrap_or(0o644));

    if dry_run {
        return ActionResult::success(
            "set_permissions",
            format!("[dry-run] chmod {permissions} {}", p.display()),
        );
    }

    use std::os::unix::fs::PermissionsExt;
    match std::fs::set_permissions(p, std::fs::Permissions::from_mode(mode)) {
        Ok(()) => ActionResult::success("set_permissions", format!("chmod {permissions}")),
        Err(e) => ActionResult::failure("set_permissions", e.to_string()),
    }
}

fn execute_tag(file: &FileInfo, tags: &[String], dry_run: bool) -> ActionResult {
    let p = &file.path;
    if dry_run {
        return ActionResult::success(
            "tag",
            format!("[dry-run] tag {:?} on {}", tags, p.display()),
        );
    }

    let current = xattr::get(p, "user.tags")
        .ok()
        .flatten()
        .and_then(|v| String::from_utf8(v).ok())
        .unwrap_or_default();
    let mut existing: std::collections::BTreeSet<String> = if current.is_empty() {
        Default::default()
    } else {
        current.split(',').map(String::from).collect()
    };
    existing.extend(tags.iter().cloned());
    let merged: Vec<String> = existing.into_iter().collect();
    let merged_str = merged.join(",");

    match xattr::set(p, "user.tags", merged_str.as_bytes()) {
        Ok(()) => ActionResult::success("tag", format!("Tagged: {merged_str}")),
        Err(e) => ActionResult::failure("tag", e.to_string()),
    }
}

fn execute_log(
    file: &FileInfo,
    message: &str,
    destination: Option<&str>,
    dry_run: bool,
) -> ActionResult {
    let msg_tpl = if message.is_empty() {
        "Processed {filename}"
    } else {
        message
    };
    let msg = render_template(msg_tpl, file);
    let line = format!(
        "{} {msg}\n",
        chrono::Local::now().format("%Y-%m-%dT%H:%M:%S")
    );

    if !dry_run {
        if let Some(dest_tpl) = destination {
            let log_path = resolve_destination(dest_tpl, file);
            if let Some(p) = log_path.parent() {
                let _ = std::fs::create_dir_all(p);
            }
            if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(&log_path)
            {
                let _ = f.write_all(line.as_bytes());
            }
        }
    }

    ActionResult::success("log", msg)
}

fn execute_open(file: &FileInfo, command: Option<&str>, dry_run: bool) -> ActionResult {
    let p = &file.path;
    if dry_run {
        return ActionResult::success("open", format!("[dry-run] open {}", p.display()));
    }
    let cmd = command.unwrap_or("xdg-open");
    match std::process::Command::new(cmd)
        .arg(p)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
    {
        Ok(_) => ActionResult::success("open", format!("Opened {}", p.display())),
        Err(e) => ActionResult::failure("open", e.to_string()),
    }
}

fn execute_create_folder(file: &FileInfo, destination: &str, dry_run: bool) -> ActionResult {
    let dest = resolve_destination(destination, file);
    if dry_run {
        return ActionResult {
            action_type: "create_folder".to_string(),
            success: true,
            message: format!("[dry-run] mkdir {}", dest.display()),
            source: Some(file.path.clone()),
            destination: Some(dest),
            error: String::new(),
        };
    }
    match std::fs::create_dir_all(&dest) {
        Ok(()) => ActionResult {
            action_type: "create_folder".to_string(),
            success: true,
            message: format!("Created {}", dest.display()),
            source: Some(file.path.clone()),
            destination: Some(dest),
            error: String::new(),
        },
        Err(e) => ActionResult::failure("create_folder", e.to_string()),
    }
}

// ─── Archive helpers ─────────────────────────────────────────────────────────

fn compress_zip(src: &Path, dest: &Path) -> anyhow::Result<()> {
    use zip::write::SimpleFileOptions;

    let file = std::fs::File::create(dest)?;
    let mut zip = zip::ZipWriter::new(file);
    let opts = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);

    if src.is_file() {
        let name = src.file_name().unwrap_or_default().to_string_lossy();
        zip.start_file(name.as_ref(), opts)?;
        zip.write_all(&std::fs::read(src)?)?;
    } else {
        for entry in walkdir::WalkDir::new(src) {
            let entry = entry?;
            let path = entry.path();
            let rel = path.strip_prefix(src.parent().unwrap_or(Path::new(".")))?;
            if path.is_file() {
                zip.start_file(rel.to_string_lossy().as_ref(), opts)?;
                zip.write_all(&std::fs::read(path)?)?;
            } else if path.is_dir() && path != src {
                zip.add_directory::<_, ()>(rel.to_string_lossy().as_ref(), Default::default())?;
            }
        }
    }
    zip.finish()?;
    Ok(())
}

fn compress_tar_gz(src: &Path, dest: &Path) -> anyhow::Result<()> {
    let file = std::fs::File::create(dest)?;
    let gz = flate2::write::GzEncoder::new(file, flate2::Compression::default());
    let mut builder = tar::Builder::new(gz);
    append_to_tar(&mut builder, src)?;
    let gz = builder.into_inner()?;
    gz.finish()?;
    Ok(())
}

fn compress_tar_bz2(src: &Path, dest: &Path) -> anyhow::Result<()> {
    let file = std::fs::File::create(dest)?;
    let bz = bzip2::write::BzEncoder::new(file, bzip2::Compression::default());
    let mut builder = tar::Builder::new(bz);
    append_to_tar(&mut builder, src)?;
    let bz = builder.into_inner()?;
    bz.finish()?;
    Ok(())
}

fn compress_tar(src: &Path, dest: &Path) -> anyhow::Result<()> {
    let file = std::fs::File::create(dest)?;
    let mut builder = tar::Builder::new(file);
    append_to_tar(&mut builder, src)?;
    builder.into_inner()?;
    Ok(())
}

fn append_to_tar<W: std::io::Write>(
    builder: &mut tar::Builder<W>,
    src: &Path,
) -> anyhow::Result<()> {
    let name = src.file_name().unwrap_or_default().to_string_lossy();
    if src.is_dir() {
        builder.append_dir_all(name.as_ref(), src)?;
    } else {
        builder.append_path_with_name(src, name.as_ref())?;
    }
    Ok(())
}

// ─── File system helpers ─────────────────────────────────────────────────────

fn copy_path(src: &Path, dest: &Path) -> std::io::Result<()> {
    if src.is_dir() {
        std::fs::create_dir_all(dest)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            copy_path(&entry.path(), &dest.join(entry.file_name()))?;
        }
    } else {
        std::fs::copy(src, dest)?;
    }
    Ok(())
}

fn remove_path(p: &Path) -> std::io::Result<()> {
    if p.is_dir() {
        std::fs::remove_dir_all(p)
    } else {
        std::fs::remove_file(p)
    }
}
