use std::fmt;
use std::path::{Path, PathBuf};

use walkdir::WalkDir;

use crate::rule::FolderConfig;

pub const PROJECT_MARKERS: &[&str] = &[
    ".git",
    "Cargo.toml",
    "package.json",
    "pyproject.toml",
    "go.mod",
    "pom.xml",
    "Gemfile",
    "composer.json",
    "mix.exs",
    "deno.json",
    // Windows / cross-platform project markers
    ".sln",        // Visual Studio solution
    ".csproj",     // C# project
    ".vbproj",     // VB.NET project
    "CMakeLists.txt",
    "Makefile",
    "gradle.build",
    "build.gradle",
    "settings.gradle",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkipReason {
    OutsideWatchedRoot {
        watched_root: PathBuf,
    },
    NestedFolderProtected {
        watched_root: PathBuf,
        depth: usize,
    },
    ExceedsAllowedDepth {
        watched_root: PathBuf,
        depth: usize,
        allowed_depth: usize,
    },
    ProjectRootProtected {
        project_root: PathBuf,
        marker: String,
    },
}

impl fmt::Display for SkipReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SkipReason::OutsideWatchedRoot { watched_root } => {
                write!(f, "outside watched root {}", watched_root.display())
            }
            SkipReason::NestedFolderProtected {
                watched_root,
                depth,
            } => {
                write!(
                    f,
                    "nested folder protected by non-recursive scope {} (depth {depth})",
                    watched_root.display()
                )
            }
            SkipReason::ExceedsAllowedDepth {
                watched_root,
                depth,
                allowed_depth,
            } => {
                write!(
                    f,
                    "outside allowed depth {allowed_depth} for {} (depth {depth})",
                    watched_root.display()
                )
            }
            SkipReason::ProjectRootProtected {
                project_root,
                marker,
            } => {
                write!(
                    f,
                    "inside protected project root {} (marker {marker})",
                    project_root.display()
                )
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct ScopeDecision {
    pub watched_root: PathBuf,
    pub relative_depth: usize,
    pub skip_reason: Option<SkipReason>,
}

impl ScopeDecision {
    pub fn allowed(&self) -> bool {
        self.skip_reason.is_none()
    }
}

pub fn evaluate_path_scope(path: &Path, folder: &FolderConfig) -> ScopeDecision {
    let watched_root = folder.expanded_path();
    let depth = relative_depth(path, &watched_root);

    let Some(relative_depth) = depth else {
        return ScopeDecision {
            watched_root: watched_root.clone(),
            relative_depth: 0,
            skip_reason: Some(SkipReason::OutsideWatchedRoot { watched_root }),
        };
    };

    if !folder.recursive && relative_depth > 1 {
        return ScopeDecision {
            watched_root: watched_root.clone(),
            relative_depth,
            skip_reason: Some(SkipReason::NestedFolderProtected {
                watched_root,
                depth: relative_depth,
            }),
        };
    }

    let allowed_depth = folder.depth.max(0) as usize;
    if folder.recursive && allowed_depth > 0 && relative_depth > allowed_depth {
        return ScopeDecision {
            watched_root: watched_root.clone(),
            relative_depth,
            skip_reason: Some(SkipReason::ExceedsAllowedDepth {
                watched_root,
                depth: relative_depth,
                allowed_depth,
            }),
        };
    }

    if !folder.allow_project_roots {
        if let Some((project_root, marker)) = find_project_root(path, &watched_root) {
            return ScopeDecision {
                watched_root,
                relative_depth,
                skip_reason: Some(SkipReason::ProjectRootProtected {
                    project_root,
                    marker,
                }),
            };
        }
    }

    ScopeDecision {
        watched_root,
        relative_depth,
        skip_reason: None,
    }
}

pub fn relative_depth(path: &Path, watched_root: &Path) -> Option<usize> {
    let path = normalize_existing(path);
    let watched_root = normalize_existing(watched_root);
    let rel = path.strip_prefix(&watched_root).ok()?;
    Some(rel.components().count())
}

pub fn find_project_root(path: &Path, watched_root: &Path) -> Option<(PathBuf, String)> {
    let watched_root = normalize_existing(watched_root);
    let mut cur = if path.is_dir() {
        normalize_existing(path)
    } else {
        normalize_existing(path.parent()?)
    };

    loop {
        if !cur.starts_with(&watched_root) {
            return None;
        }

        for marker in PROJECT_MARKERS {
            if cur.join(marker).exists() {
                return Some((cur, (*marker).to_string()));
            }
        }

        if cur == watched_root {
            return None;
        }
        cur = cur.parent()?.to_path_buf();
    }
}

pub fn scan_folder_files(folder: &FolderConfig) -> Vec<PathBuf> {
    let root = folder.expanded_path();
    if !root.exists() {
        return Vec::new();
    }

    if !folder.recursive {
        return std::fs::read_dir(root)
            .into_iter()
            .flatten()
            .filter_map(|entry| entry.ok().map(|entry| entry.path()))
            .filter(|path| path.is_file())
            .collect();
    }

    WalkDir::new(root)
        .into_iter()
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.into_path())
        .filter(|path| path.is_file())
        .collect()
}

fn normalize_existing(path: &Path) -> PathBuf {
    std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}
