use serde_json::{Map, Value};
use std::io::Write;
use std::path::PathBuf;

pub fn path() -> PathBuf {
    crate::paths::config_home().join("quickshell").join("settings.json")
}

fn put(root: &mut Value, key: &str, v: Value) {
    let mut node = root;
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

#[derive(Clone, Debug, Default)]
pub struct Settings {
    pub value: Value,
    /// What `set` changed: `save` puts only these into the file as it is then, so what the shell or Settings wrote
    /// in the meantime isn't undone (several programs write settings.json).
    changed: Vec<(String, Value)>,
}

impl Settings {
    pub fn load() -> Self {
        let value = std::fs::read_to_string(path())
            .ok()
            .and_then(|s| serde_json::from_str::<Value>(&s).ok())
            .filter(Value::is_object)
            .unwrap_or_else(|| Value::Object(Map::new()));
        Settings { value, changed: vec![] }
    }

    pub fn from_value(value: Value) -> Self {
        Settings { value, changed: vec![] }
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
        self.changed.retain(|(k, _)| k != key);
        self.changed.push((key.to_string(), v.clone()));
        put(&mut self.value, key, v);
    }

    pub fn save(&self) -> std::io::Result<()> {
        let path = path();
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        // The file as it is now, with this program's changes on top.
        let mut now = Settings::load().value;
        if self.changed.is_empty() && !path.exists() {
            now = self.value.clone();
        }
        for (k, v) in &self.changed {
            put(&mut now, k, v.clone());
        }
        let tmp = path.with_extension(format!("json.{}.tmp", std::process::id()));
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(serde_json::to_string_pretty(&now)?.as_bytes())?;
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
        if self.dark() { self.str("theme.accent", "mauve") } else { self.str("theme.accentLight", "mauve") }
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
        let s = Settings::from_value(json!({ "theme": { "flavor": 5, "accent": "teal" } }));
        assert_eq!(s.flavour(), "mocha");
        assert_eq!(s.accent_name(), "teal");
        assert_eq!(s.f64("theme.animationSpeed", 1.0), 1.0);
    }

    #[test]
    fn set_keeps_the_rest() {
        let mut s = Settings::from_value(json!({ "theme": { "flavor": "latte", "mine": 1 }, "other": true }));
        s.set("theme.accentLight", json!("blue"));
        s.set("new.deep.key", json!(2));
        assert_eq!(s.value["theme"]["mine"], 1);
        assert_eq!(s.value["other"], true);
        assert_eq!(s.accent_name(), "blue");
        assert_eq!(s.value["new"]["deep"]["key"], 2);
    }

    #[test]
    fn save_keeps_what_others_wrote_meanwhile() {
        let dir = std::env::temp_dir().join(format!("vyntaris-settings-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("quickshell")).unwrap();
        // SAFETY: this test is the only one that reads the config folder from the environment
        unsafe { std::env::set_var("XDG_CONFIG_HOME", &dir) };
        std::fs::write(path(), r#"{"theme": {"accent": "mauve"}}"#).unwrap();
        let mut mine = Settings::load();
        // the shell writes while this program holds its copy
        std::fs::write(path(), r#"{"theme": {"accent": "blue"}, "bar": {"height": 32}}"#).unwrap();
        mine.set("apps.aur", json!(true));
        mine.save().unwrap();
        let now = Settings::load();
        assert_eq!(now.str("theme.accent", ""), "blue");
        assert_eq!(now.f64("bar.height", 0.0), 32.0);
        assert!(now.bool("apps.aur", false));
        let _ = std::fs::remove_dir_all(dir);
    }
}
