use std::path::Path;

use crate::rule::RuleConfig;

pub fn load_rule_file(path: &Path) -> anyhow::Result<RuleConfig> {
    let text = std::fs::read_to_string(path)?;
    let mut rule: RuleConfig = serde_json::from_str(&text)?;
    rule.source_file = Some(path.to_path_buf());
    Ok(rule)
}

pub fn save_rule_file(rule: &RuleConfig, path: &Path) -> anyhow::Result<()> {
    let json = serde_json::to_string_pretty(rule)?;
    std::fs::write(path, json)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn all_example_rules_deserialize() {
        let examples = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../examples/rules");

        let entries: Vec<_> = std::fs::read_dir(&examples)
            .expect("examples/rules not found")
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map_or(false, |x| x == "json"))
            .collect();

        assert!(!entries.is_empty(), "No example rules found");

        for entry in entries {
            let path = entry.path();
            let json = std::fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("Cannot read {:?}: {}", path, e));
            let rule: RuleConfig = serde_json::from_str(&json)
                .unwrap_or_else(|e| panic!("Failed to parse {:?}: {}", path, e));
            assert!(!rule.name.is_empty(), "Rule in {:?} has empty name", path);
        }
    }

    #[test]
    fn roundtrip_serialize() {
        let examples = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../examples/rules");

        for entry in std::fs::read_dir(&examples)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().map_or(false, |x| x == "json"))
        {
            let path = entry.path();
            let original = std::fs::read_to_string(&path).unwrap();
            let rule: RuleConfig = serde_json::from_str(&original).unwrap();
            let serialized = serde_json::to_string_pretty(&rule).unwrap();
            // Deserialize again to verify
            let _: RuleConfig = serde_json::from_str(&serialized)
                .unwrap_or_else(|e| panic!("Re-parse failed for {:?}: {}", path, e));
        }
    }
}
