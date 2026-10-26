use regex::Regex;
use serde_json::{Map, Value};
use std::fs;
use std::path::Path;

const VALUE: &str = r#"("(?:[^"\\]|\\.)*"|true|false|null|-?\d+(?:\.\d+)?)"#;

pub fn set_keys(text: &str, keys: &Map<String, Value>) -> String {
    let mut new = text.to_string();
    for (key, value) in keys {
        let val = serde_json::to_string(value).expect("a value");
        let pat = Regex::new(&format!(r#"("{}"\s*:\s*){VALUE}"#, regex::escape(key))).expect("a pattern");
        if pat.is_match(&new) {
            new = pat.replacen(&new, 1, |c: &regex::Captures| format!("{}{val}", &c[1])).into_owned();
        } else {
            let line = format!("{{\n    {}: {val},", serde_json::to_string(key).expect("a key"));
            new = new.replacen('{', &line, 1);
        }
    }
    new
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (Some(config), Some(Ok(Value::Object(keys)))) = (args.first(), args.get(1).map(|k| serde_json::from_str::<Value>(k))) else {
        eprintln!("vscode-theme CONFIG_HOME '{{\"key\": value}}'");
        std::process::exit(2);
    };
    for app in ["Code - OSS", "Code"] {
        let folder = Path::new(config).join(app).join("User");
        if !folder.is_dir() {
            continue;
        }
        let path = folder.join("settings.json");
        let text = fs::read_to_string(&path).unwrap_or_else(|_| "{\n}\n".into());
        let new = set_keys(&text, &keys);
        if new != text {
            let _ = fs::write(&path, new);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_where_it_is_added_where_it_isnt() {
        let text = "{\n    // mine\n    \"workbench.colorTheme\": \"Default Dark\",\n    \"editor.fontSize\": 14\n}\n";
        let keys: Map<String, Value> = serde_json::from_str(r#"{"workbench.colorTheme": "Catppuccin Mocha", "catppuccin.accentColor": "mauve"}"#).unwrap();
        let out = set_keys(text, &keys);
        assert!(out.contains("\"workbench.colorTheme\": \"Catppuccin Mocha\""));
        assert!(out.starts_with("{\n    \"catppuccin.accentColor\": \"mauve\","));
        assert!(out.contains("// mine") && out.contains("\"editor.fontSize\": 14"));
        assert_eq!(set_keys(&out, &keys), out, "a second time changes nothing");
    }
}
