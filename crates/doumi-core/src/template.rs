use chrono::Local;
use once_cell::sync::Lazy;
use regex::Regex;
use std::path::{Path, PathBuf};

use crate::models::FileInfo;

static TEMPLATE_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\{(\w[^}]*)\}").unwrap());

pub fn mime_kind(mime: &str) -> &'static str {
    if mime.is_empty() {
        return "other";
    }
    if mime.starts_with("image/") {
        return "image";
    }
    if mime.starts_with("video/") {
        return "video";
    }
    if mime.starts_with("audio/") {
        return "audio";
    }
    if mime.starts_with("font/") {
        return "font";
    }
    for pfx in &[
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats",
        "application/vnd.oasis",
        "text/plain",
        "text/rtf",
    ] {
        if mime.starts_with(pfx) {
            return "document";
        }
    }
    for pfx in &[
        "application/zip",
        "application/x-tar",
        "application/x-rar",
        "application/x-7z",
        "application/gzip",
        "application/x-bzip",
    ] {
        if mime.starts_with(pfx) {
            return "archive";
        }
    }
    for pfx in &[
        "text/x-",
        "application/x-sh",
        "application/javascript",
        "text/javascript",
    ] {
        if mime.starts_with(pfx) {
            return "code";
        }
    }
    for pfx in &["application/x-executable", "application/x-elf"] {
        if mime.starts_with(pfx) {
            return "executable";
        }
    }
    for pfx in &["application/vnd.ms-excel", "text/csv"] {
        if mime.starts_with(pfx) {
            return "spreadsheet";
        }
    }
    "other"
}

pub fn render_template(template: &str, file: &FileInfo) -> String {
    let dt_mod = file.date_modified.unwrap_or_else(Local::now);
    let dt_cre = file.date_created.unwrap_or_else(Local::now);

    TEMPLATE_RE
        .replace_all(template, |caps: &regex::Captures| {
            let key = &caps[1];
            if let Some((k, fmt)) = key.split_once(':') {
                if k.starts_with("date") {
                    return dt_mod.format(fmt).to_string();
                }
            }
            match key {
                "name" => file.stem.clone(),
                "filename" => file.name.clone(),
                "ext" => format!(".{}", file.extension),
                "extension" => file.extension.clone(),
                "parent" => file
                    .path
                    .parent()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_default(),
                "year" => dt_mod.format("%Y").to_string(),
                "month" => dt_mod.format("%m").to_string(),
                "month_name" => dt_mod.format("%B").to_string(),
                "month_abbr" => dt_mod.format("%b").to_string(),
                "day" => dt_mod.format("%d").to_string(),
                "hour" => dt_mod.format("%H").to_string(),
                "minute" => dt_mod.format("%M").to_string(),
                "date" => dt_mod.format("%Y-%m-%d").to_string(),
                "datetime" => dt_mod.format("%Y-%m-%d_%H-%M-%S").to_string(),
                "created_year" => dt_cre.format("%Y").to_string(),
                "created_month" => dt_cre.format("%m").to_string(),
                "created_month_name" => dt_cre.format("%B").to_string(),
                "created_day" => dt_cre.format("%d").to_string(),
                "today" => Local::now().format("%Y-%m-%d").to_string(),
                "size" => file.size.to_string(),
                "mime_type" => file.mime_type.clone(),
                "kind" => mime_kind(&file.mime_type).to_string(),
                _ => caps[0].to_string(),
            }
        })
        .to_string()
}

pub fn resolve_destination(template: &str, file: &FileInfo) -> PathBuf {
    let rendered = render_template(template, file);
    PathBuf::from(shellexpand::tilde(&rendered).as_ref())
}

pub fn unique_path(dest: PathBuf) -> PathBuf {
    if !dest.exists() {
        return dest;
    }
    let stem = dest
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let ext = dest
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    let parent = dest.parent().unwrap_or(Path::new(".")).to_path_buf();
    let mut counter = 1u32;
    loop {
        let candidate = parent.join(format!("{stem}_{counter}{ext}"));
        if !candidate.exists() {
            return candidate;
        }
        counter += 1;
    }
}

pub fn size_to_bytes(value: f64, unit: &str) -> u64 {
    let unit = unit.to_lowercase();
    let unit = unit.trim_end_matches('s');
    let factor: f64 = match unit {
        "b" | "byte" => 1.0,
        "kb" | "kilobyte" => 1024.0,
        "mb" | "megabyte" => 1024.0 * 1024.0,
        "gb" | "gigabyte" => 1024.0 * 1024.0 * 1024.0,
        "tb" | "terabyte" => 1024.0 * 1024.0 * 1024.0 * 1024.0,
        _ => 1.0,
    };
    (value * factor) as u64
}

pub fn time_to_seconds(value: f64, unit: &str) -> f64 {
    let unit = unit.to_lowercase();
    let unit = if unit.ends_with('s') {
        unit.as_str()
    } else {
        &format!("{unit}s")
    };
    match unit {
        "seconds" => value,
        "minutes" => value * 60.0,
        "hours" => value * 3600.0,
        "days" => value * 86400.0,
        "weeks" => value * 604800.0,
        "months" => value * 2592000.0,
        "years" => value * 31536000.0,
        _ => value * 86400.0,
    }
}
