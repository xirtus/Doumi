use chrono::{DateTime, Local};
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct FileInfo {
    pub path: PathBuf,
    pub name: String,
    pub stem: String,
    pub extension: String,
    pub size: u64,
    pub date_created: Option<DateTime<Local>>,
    pub date_modified: Option<DateTime<Local>>,
    pub date_accessed: Option<DateTime<Local>>,
    pub mime_type: String,
    pub is_dir: bool,
    pub is_symlink: bool,
}

impl FileInfo {
    pub fn from_path(path: &std::path::Path) -> anyhow::Result<Self> {
        let meta = path.symlink_metadata()?;
        let is_symlink = meta.file_type().is_symlink();
        let is_dir = path.is_dir();
        let size = if is_dir { 0 } else { meta.len() };

        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let stem = path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        let extension = path
            .extension()
            .map(|e| e.to_string_lossy().to_lowercase())
            .unwrap_or_default();

        let date_created = meta.created().ok().map(DateTime::<Local>::from);
        let date_modified = meta.modified().ok().map(DateTime::<Local>::from);
        let date_accessed = meta.accessed().ok().map(DateTime::<Local>::from);

        let mime_type = if !is_dir {
            infer::get_from_path(path)
                .ok()
                .flatten()
                .map(|k| k.mime_type().to_string())
                .unwrap_or_default()
        } else {
            String::new()
        };

        Ok(Self {
            path: path.to_path_buf(),
            name,
            stem,
            extension,
            size,
            date_created,
            date_modified,
            date_accessed,
            mime_type,
            is_dir,
            is_symlink,
        })
    }
}

#[derive(Debug, Clone, Default)]
pub struct ActionResult {
    pub action_type: String,
    pub success: bool,
    pub message: String,
    pub source: Option<PathBuf>,
    pub destination: Option<PathBuf>,
    pub error: String,
}

impl ActionResult {
    pub fn success(action_type: &str, msg: impl Into<String>) -> Self {
        Self {
            action_type: action_type.to_string(),
            success: true,
            message: msg.into(),
            ..Default::default()
        }
    }

    pub fn failure(action_type: &str, error: impl Into<String>) -> Self {
        Self {
            action_type: action_type.to_string(),
            success: false,
            error: error.into(),
            ..Default::default()
        }
    }

    pub fn with_paths(mut self, src: PathBuf, dest: PathBuf) -> Self {
        self.source = Some(src);
        self.destination = Some(dest);
        self
    }
}

#[derive(Debug, Clone)]
pub struct ProcessingResult {
    pub file_path: PathBuf,
    pub rule_id: String,
    pub rule_name: String,
    pub matched: bool,
    pub dry_run: bool,
    pub skip_reason: Option<String>,
    pub action_results: Vec<ActionResult>,
    pub timestamp: DateTime<Local>,
}

impl ProcessingResult {
    pub fn new(
        file_path: PathBuf,
        rule_id: String,
        rule_name: String,
        matched: bool,
        dry_run: bool,
    ) -> Self {
        Self {
            file_path,
            rule_id,
            rule_name,
            matched,
            dry_run,
            skip_reason: None,
            action_results: vec![],
            timestamp: Local::now(),
        }
    }

    pub fn skipped(
        file_path: PathBuf,
        rule_id: String,
        rule_name: String,
        dry_run: bool,
        reason: impl Into<String>,
    ) -> Self {
        let mut result = Self::new(file_path, rule_id, rule_name, false, dry_run);
        result.skip_reason = Some(reason.into());
        result
    }

    pub fn all_success(&self) -> bool {
        self.action_results.iter().all(|r| r.success)
    }
}
