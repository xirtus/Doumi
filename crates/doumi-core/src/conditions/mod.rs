use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::path::PathBuf;

use crate::models::FileInfo;
use crate::template::{mime_kind, size_to_bytes, time_to_seconds};

// ─── Helper: string-or-vec ───────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum StringOrVec {
    One(String),
    Many(Vec<String>),
}

impl StringOrVec {
    pub fn to_vec(&self) -> Vec<String> {
        match self {
            Self::One(s) => vec![s.clone()],
            Self::Many(v) => v.clone(),
        }
    }
}

impl<'de> Deserialize<'de> for StringOrVec {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Inner {
            One(String),
            Many(Vec<String>),
        }
        Ok(match Inner::deserialize(d)? {
            Inner::One(s) => StringOrVec::One(s),
            Inner::Many(v) => StringOrVec::Many(v),
        })
    }
}

impl Serialize for StringOrVec {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        match self {
            StringOrVec::One(v) => s.serialize_str(v),
            StringOrVec::Many(v) => v.serialize(s),
        }
    }
}

// ─── Size value (scalar or [lo, hi] for between) ─────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum SizeValue {
    Single(f64),
    Range(Vec<f64>),
}

// ─── MatchMode ───────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum MatchMode {
    #[default]
    All,
    Any,
    None,
}

// ─── Operator enums with alias support ───────────────────────────────────────

#[derive(Debug, Clone)]
pub enum StringOp {
    Is,
    IsNot,
    Contains,
    NotContains,
    StartsWith,
    EndsWith,
    MatchesGlob,
    MatchesRegex,
    IsOneOf,
    IsNotOneOf,
}

impl<'de> Deserialize<'de> for StringOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "is" => StringOp::Is,
            "is_not" => StringOp::IsNot,
            "contains" => StringOp::Contains,
            "not_contains" => StringOp::NotContains,
            "starts_with" => StringOp::StartsWith,
            "ends_with" => StringOp::EndsWith,
            "matches_glob" => StringOp::MatchesGlob,
            "matches_regex" => StringOp::MatchesRegex,
            "is_one_of" => StringOp::IsOneOf,
            "is_not_one_of" => StringOp::IsNotOneOf,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &[
                        "is",
                        "is_not",
                        "contains",
                        "starts_with",
                        "ends_with",
                        "matches_glob",
                        "matches_regex",
                        "is_one_of",
                        "is_not_one_of",
                    ],
                ))
            }
        })
    }
}

impl Serialize for StringOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            StringOp::Is => "is",
            StringOp::IsNot => "is_not",
            StringOp::Contains => "contains",
            StringOp::NotContains => "not_contains",
            StringOp::StartsWith => "starts_with",
            StringOp::EndsWith => "ends_with",
            StringOp::MatchesGlob => "matches_glob",
            StringOp::MatchesRegex => "matches_regex",
            StringOp::IsOneOf => "is_one_of",
            StringOp::IsNotOneOf => "is_not_one_of",
        })
    }
}

#[derive(Debug, Clone)]
pub enum ListOp {
    Is,
    IsNot,
    IsOneOf,
    IsNotOneOf,
}

impl<'de> Deserialize<'de> for ListOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "is" => ListOp::Is,
            "is_not" => ListOp::IsNot,
            "is_one_of" => ListOp::IsOneOf,
            "is_not_one_of" => ListOp::IsNotOneOf,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["is", "is_not", "is_one_of", "is_not_one_of"],
                ))
            }
        })
    }
}

impl Serialize for ListOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            ListOp::Is => "is",
            ListOp::IsNot => "is_not",
            ListOp::IsOneOf => "is_one_of",
            ListOp::IsNotOneOf => "is_not_one_of",
        })
    }
}

#[derive(Debug, Clone)]
pub enum SizeOp {
    Gt,
    Lt,
    Eq,
    Between,
}

impl<'de> Deserialize<'de> for SizeOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "greater_than" | "gt" => SizeOp::Gt,
            "less_than" | "lt" => SizeOp::Lt,
            "equal_to" | "eq" => SizeOp::Eq,
            "between" => SizeOp::Between,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["greater_than", "less_than", "equal_to", "between"],
                ))
            }
        })
    }
}

impl Serialize for SizeOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            SizeOp::Gt => "greater_than",
            SizeOp::Lt => "less_than",
            SizeOp::Eq => "equal_to",
            SizeOp::Between => "between",
        })
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SizeUnit {
    Bytes,
    B,
    #[default]
    Kb,
    Mb,
    Gb,
    Tb,
}

impl SizeUnit {
    pub fn to_bytes(&self, v: f64) -> u64 {
        size_to_bytes(v, &format!("{self:?}").to_lowercase())
    }
}

#[derive(Debug, Clone)]
pub enum AgeOp {
    OlderThan,
    NewerThan,
}

impl<'de> Deserialize<'de> for AgeOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "older_than" | "gt" => AgeOp::OlderThan,
            "newer_than" | "lt" => AgeOp::NewerThan,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["older_than", "newer_than"],
                ))
            }
        })
    }
}

impl Serialize for AgeOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            AgeOp::OlderThan => "older_than",
            AgeOp::NewerThan => "newer_than",
        })
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimeUnit {
    Seconds,
    Minutes,
    Hours,
    #[default]
    Days,
    Weeks,
    Months,
    Years,
}

impl TimeUnit {
    pub fn to_seconds(&self, v: f64) -> f64 {
        let unit = format!("{self:?}").to_lowercase();
        time_to_seconds(v, &unit)
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DateField {
    Created,
    #[default]
    Modified,
    Accessed,
}

#[derive(Debug, Clone)]
pub enum CmpOp {
    Eq,
    Lt,
    Gt,
}

impl<'de> Deserialize<'de> for CmpOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "equal_to" | "eq" => CmpOp::Eq,
            "less_than" | "lt" => CmpOp::Lt,
            "greater_than" | "gt" => CmpOp::Gt,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["equal_to", "less_than", "greater_than"],
                ))
            }
        })
    }
}

impl Serialize for CmpOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            CmpOp::Eq => "equal_to",
            CmpOp::Lt => "less_than",
            CmpOp::Gt => "greater_than",
        })
    }
}

#[derive(Debug, Clone)]
pub enum TextOp {
    Contains,
    NotContains,
    MatchesRegex,
}

impl<'de> Deserialize<'de> for TextOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "contains" => TextOp::Contains,
            "not_contains" => TextOp::NotContains,
            "matches_regex" => TextOp::MatchesRegex,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["contains", "not_contains", "matches_regex"],
                ))
            }
        })
    }
}

impl Serialize for TextOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            TextOp::Contains => "contains",
            TextOp::NotContains => "not_contains",
            TextOp::MatchesRegex => "matches_regex",
        })
    }
}

#[derive(Debug, Clone)]
pub enum PermOp {
    IsReadable,
    IsWritable,
    IsExecutable,
}

impl<'de> Deserialize<'de> for PermOp {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Ok(match s.as_str() {
            "is_readable" => PermOp::IsReadable,
            "is_writable" => PermOp::IsWritable,
            "is_executable" => PermOp::IsExecutable,
            _ => {
                return Err(serde::de::Error::unknown_variant(
                    &s,
                    &["is_readable", "is_writable", "is_executable"],
                ))
            }
        })
    }
}

impl Serialize for PermOp {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            PermOp::IsReadable => "is_readable",
            PermOp::IsWritable => "is_writable",
            PermOp::IsExecutable => "is_executable",
        })
    }
}

// ─── The main Condition enum ─────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Condition {
    Group {
        #[serde(rename = "match", default)]
        match_mode: MatchMode,
        #[serde(default)]
        items: Vec<Condition>,
    },
    Name {
        operator: StringOp,
        value: StringOrVec,
        #[serde(default)]
        case_sensitive: bool,
    },
    Extension {
        operator: ListOp,
        value: StringOrVec,
    },
    Size {
        operator: SizeOp,
        value: SizeValue,
        #[serde(default)]
        unit: String,
    },
    Age {
        operator: AgeOp,
        value: f64,
        #[serde(default)]
        unit: String,
        #[serde(default)]
        date_type: DateField,
    },
    MimeType {
        operator: StringOp,
        value: StringOrVec,
    },
    Kind {
        operator: ListOp,
        value: StringOrVec,
    },
    #[serde(alias = "is_folder")]
    IsDirectory {
        value: bool,
    },
    IsSymlink {
        value: bool,
    },
    // unit field reused as base_path (matches Python ConditionConfig.unit for depth)
    Depth {
        operator: CmpOp,
        value: i32,
        #[serde(default)]
        unit: String,
    },
    #[serde(alias = "contents")]
    Content {
        operator: TextOp,
        value: String,
    },
    Permissions {
        operator: PermOp,
    },
    Script {
        command: String,
        #[serde(default = "default_bash")]
        interpreter: String,
    },
}

fn default_bash() -> String {
    "bash".to_string()
}

// ─── Evaluation ──────────────────────────────────────────────────────────────

impl Condition {
    pub fn evaluate(&self, file: &FileInfo) -> bool {
        match self {
            Condition::Group { match_mode, items } => {
                if items.is_empty() {
                    return true;
                }
                match match_mode {
                    MatchMode::All => items.iter().all(|c| c.evaluate(file)),
                    MatchMode::Any => items.iter().any(|c| c.evaluate(file)),
                    MatchMode::None => !items.iter().any(|c| c.evaluate(file)),
                }
            }

            Condition::Name {
                operator,
                value,
                case_sensitive,
            } => {
                let prep = |s: &str| -> String {
                    if *case_sensitive {
                        s.to_string()
                    } else {
                        s.to_lowercase()
                    }
                };
                let name = prep(&file.name);
                let stem = prep(&file.stem);
                let values: Vec<String> = value.to_vec().iter().map(|v| prep(v)).collect();

                match operator {
                    StringOp::Is => values.iter().any(|v| name == *v || stem == *v),
                    StringOp::IsNot => values.iter().all(|v| name != *v && stem != *v),
                    StringOp::Contains => values.iter().any(|v| name.contains(v.as_str())),
                    StringOp::NotContains => values.iter().all(|v| !name.contains(v.as_str())),
                    StringOp::StartsWith => values.iter().any(|v| name.starts_with(v.as_str())),
                    StringOp::EndsWith => values.iter().any(|v| stem.ends_with(v.as_str())),
                    StringOp::MatchesGlob => values
                        .iter()
                        .any(|v| glob::Pattern::new(v).map_or(false, |p| p.matches(&name))),
                    StringOp::MatchesRegex => {
                        let flags = if *case_sensitive { "" } else { "(?i)" };
                        values.iter().any(|v| {
                            regex::Regex::new(&format!("{flags}{v}"))
                                .map_or(false, |re| re.is_match(&name))
                        })
                    }
                    StringOp::IsOneOf => values.iter().any(|v| name == *v || stem == *v),
                    StringOp::IsNotOneOf => values.iter().all(|v| name != *v && stem != *v),
                }
            }

            Condition::Extension { operator, value } => {
                let ext = file.extension.to_lowercase();
                let values: Vec<String> = value
                    .to_vec()
                    .iter()
                    .map(|v| v.trim_start_matches('.').to_lowercase())
                    .collect();
                match operator {
                    ListOp::Is | ListOp::IsOneOf => values.contains(&ext),
                    ListOp::IsNot | ListOp::IsNotOneOf => !values.contains(&ext),
                }
            }

            Condition::Size {
                operator,
                value,
                unit,
            } => {
                let to_bytes =
                    |v: f64| size_to_bytes(v, if unit.is_empty() { "bytes" } else { unit });
                let size = file.size;
                match (operator, value) {
                    (SizeOp::Gt, SizeValue::Single(v)) => size > to_bytes(*v),
                    (SizeOp::Lt, SizeValue::Single(v)) => size < to_bytes(*v),
                    (SizeOp::Eq, SizeValue::Single(v)) => size == to_bytes(*v),
                    (SizeOp::Between, SizeValue::Range(arr)) => {
                        let lo = to_bytes(arr.first().copied().unwrap_or(0.0));
                        let hi = to_bytes(arr.get(1).copied().unwrap_or(0.0));
                        let (lo, hi) = (lo.min(hi), lo.max(hi));
                        size >= lo && size <= hi
                    }
                    (SizeOp::Between, SizeValue::Single(v)) => size == to_bytes(*v),
                    _ => false,
                }
            }

            Condition::Age {
                operator,
                value,
                unit,
                date_type,
            } => {
                let unit_str = if unit.is_empty() { "days" } else { unit };
                let threshold_secs = time_to_seconds(*value, unit_str);
                let dt = match date_type {
                    DateField::Created => file.date_created,
                    DateField::Accessed => file.date_accessed,
                    DateField::Modified => file.date_modified,
                };
                let age_secs = dt
                    .map(|d| (chrono::Local::now() - d).num_seconds().max(0) as f64)
                    .unwrap_or(0.0);
                match operator {
                    AgeOp::OlderThan => age_secs > threshold_secs,
                    AgeOp::NewerThan => age_secs < threshold_secs,
                }
            }

            Condition::MimeType { operator, value } => {
                let mime = file.mime_type.to_lowercase();
                let values: Vec<String> = value.to_vec().iter().map(|v| v.to_lowercase()).collect();
                match operator {
                    StringOp::Is | StringOp::IsOneOf => values.iter().any(|v| mime == *v),
                    StringOp::IsNot | StringOp::IsNotOneOf => values.iter().all(|v| mime != *v),
                    StringOp::StartsWith => values.iter().any(|v| mime.starts_with(v.as_str())),
                    StringOp::Contains => values.iter().any(|v| mime.contains(v.as_str())),
                    _ => false,
                }
            }

            Condition::Kind { operator, value } => {
                let kind = if file.is_dir {
                    "folder".to_string()
                } else {
                    mime_kind(&file.mime_type).to_string()
                };
                let values = value.to_vec();
                match operator {
                    ListOp::Is | ListOp::IsOneOf => values.contains(&kind),
                    ListOp::IsNot | ListOp::IsNotOneOf => !values.contains(&kind),
                }
            }

            Condition::IsDirectory { value } => file.is_dir == *value,
            Condition::IsSymlink { value } => file.is_symlink == *value,

            Condition::Depth {
                operator,
                value,
                unit,
            } => {
                let base = PathBuf::from(shellexpand::tilde(unit).as_ref());
                if base.as_os_str().is_empty() {
                    return false;
                }
                let Ok(rel) = file.path.strip_prefix(&base) else {
                    return false;
                };
                let depth = rel.components().count() as i32;
                match operator {
                    CmpOp::Eq => depth == *value,
                    CmpOp::Lt => depth < *value,
                    CmpOp::Gt => depth > *value,
                }
            }

            Condition::Content { operator, value } => {
                const MAX_SIZE: u64 = 1024 * 1024;
                if file.is_dir || file.size > MAX_SIZE {
                    return false;
                }
                let text = match std::fs::read_to_string(&file.path) {
                    Ok(t) => t,
                    Err(_) => return false,
                };
                match operator {
                    TextOp::Contains => text.to_lowercase().contains(&value.to_lowercase()),
                    TextOp::NotContains => !text.to_lowercase().contains(&value.to_lowercase()),
                    TextOp::MatchesRegex => {
                        regex::Regex::new(value).map_or(false, |re| re.is_match(&text))
                    }
                }
            }

            Condition::Permissions { operator } => {
                use std::os::unix::fs::PermissionsExt;
                let Ok(meta) = file.path.metadata() else {
                    return false;
                };
                let mode = meta.permissions().mode();
                match operator {
                    PermOp::IsReadable => mode & 0o444 != 0,
                    PermOp::IsWritable => mode & 0o222 != 0,
                    PermOp::IsExecutable => mode & 0o111 != 0,
                }
            }

            Condition::Script {
                command,
                interpreter,
            } => {
                let cmd = shellexpand::tilde(command).to_string();
                std::process::Command::new(interpreter)
                    .arg(&cmd)
                    .arg(file.path.to_string_lossy().as_ref())
                    .output()
                    .map_or(false, |o| o.status.success())
            }
        }
    }
}
