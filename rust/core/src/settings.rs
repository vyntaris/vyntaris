use serde_json::{Map, Value};
use std::io::Write;
use std::path::PathBuf;

pub fn path() -> PathBuf {
    crate::paths::config_home().join("quickshell").join("settings.json")
}

#[derive(Clone, Debug, Default)]
pub struct Settings {
    pub value: Value,
}

impl Settings {
    pub fn load() -> Self {
        let value = std::fs::read_to_string(path())
            .ok()
            .and_then(|s| serde_json::from_str::<Value>(&s).ok())
            .filter(Value::is_object)
            .unwrap_or_else(|| Value::Object(Map::new()));
        Settings { value }
    }

    fn at(&self, key: &str) -> Option<&Value> {
        key.split('.').try_fold(&self.value, |v, k| v.get(k))
    }

    pub fn str(&self, key: &str, default: &str) -> String {
        self.at(key).and_then(Value::as_str).unwrap_or(default).to_string()
    }
    pub fn bool(&self, key: &str, default: bool) -> bool {
        self.at(key).and_then(Value::as_bool).unwrap_or(default)
    }
    pub fn f64(&self, key: &str, default: f64) -> f64 {
        self.at(key).and_then(Value::as_f64).filter(|v| v.is_finite()).unwrap_or(default)
    }

    pub fn set(&mut self, key: &str, v: Value) {
        let mut node = &mut self.value;
        let mut parts = key.split('.').peekable();
        while let Some(k) = parts.next() {
            if !node.is_object() {
                *node = Value::Object(Map::new());
            }
            let map = node.as_object_mut().expect("an object");
            if parts.peek().is_none() {
                map.insert(k.to_string(), v);
                return;
            }
            node = map.entry(k.to_string()).or_insert_with(|| Value::Object(Map::new()));
        }
    }

    pub fn save(&self) -> std::io::Result<()> {
        let path = path();
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(serde_json::to_string_pretty(&self.value)?.as_bytes())?;
        f.sync_all()?;
        std::fs::rename(tmp, path)
    }

    pub fn flavour(&self) -> String {
        self.str("theme.flavor", "mocha")
    }
    pub fn dark(&self) -> bool {
        self.flavour() != "latte"
    }
    pub fn accent_name(&self) -> String {
        if self.dark() { self.str("theme.accent", "blue") } else { self.str("theme.accentLight", "sky") }
    }
    pub fn accent(&self) -> (String, String) {
        crate::palette::accent(crate::palette::palette(&self.flavour()), &self.accent_name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn defaults_for_what_is_missing_or_wrong() {
        let s = Settings { value: json!({ "theme": { "flavor": 5, "accent": "teal" } }) };
        assert_eq!(s.flavour(), "mocha");
        assert_eq!(s.accent_name(), "teal");
        assert_eq!(s.f64("theme.animationSpeed", 1.0), 1.0);
    }

    #[test]
    fn set_keeps_the_rest() {
        let mut s = Settings { value: json!({ "theme": { "flavor": "latte", "mine": 1 }, "other": true }) };
        s.set("theme.accentLight", json!("blue"));
        s.set("new.deep.key", json!(2));
        assert_eq!(s.value["theme"]["mine"], 1);
        assert_eq!(s.value["other"], true);
        assert_eq!(s.accent_name(), "blue");
        assert_eq!(s.value["new"]["deep"]["key"], 2);
    }
}
