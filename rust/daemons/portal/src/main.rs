use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{OwnedValue, Value};

const NAMESPACE: &str = "org.freedesktop.appearance";
const PATH: &str = "/org/freedesktop/portal/desktop";

#[derive(Clone, Copy, Debug, PartialEq)]
struct Look {
    accent: (f64, f64, f64),
    scheme: u32,
}

fn gtk_css() -> PathBuf {
    vyntaris_core::paths::config_home().join("gtk-4.0").join("gtk.css")
}

fn colour(css: &str, name: &str) -> Option<(f64, f64, f64)> {
    let line = css.lines().find(|l| l.trim_start().starts_with(&format!("@define-color {name} ")))?;
    let hex = line.split_whitespace().nth(2)?.trim_end_matches(';');
    vyntaris_core::palette::is_hex(hex).then(|| vyntaris_core::palette::rgb(hex))
}

fn read(css: &str) -> Look {
    let accent = colour(css, "accent_bg_color").unwrap_or((0.796, 0.651, 0.969));
    let dark = colour(css, "window_bg_color").is_none_or(|(r, g, b)| 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5);
    Look { accent, scheme: if dark { 1 } else { 2 } }
}

impl Look {
    fn values(&self) -> HashMap<String, OwnedValue> {
        let mut out = HashMap::new();
        out.insert("accent-color".to_string(), OwnedValue::try_from(Value::from(self.accent)).expect("a value"));
        out.insert("color-scheme".to_string(), OwnedValue::from(self.scheme));
        out
    }
}

fn wanted(namespaces: &[String]) -> bool {
    namespaces.is_empty() || namespaces.iter().any(|n| n.is_empty() || n == NAMESPACE || n.strip_suffix('*').is_some_and(|p| NAMESPACE.starts_with(p)))
}

struct Settings {
    look: Arc<Mutex<Look>>,
}

#[zbus::interface(name = "org.freedesktop.impl.portal.Settings")]
impl Settings {
    async fn read_all(&self, namespaces: Vec<String>) -> HashMap<String, HashMap<String, OwnedValue>> {
        let mut out = HashMap::new();
        if wanted(&namespaces) {
            out.insert(NAMESPACE.to_string(), self.look.lock().expect("the look").values());
        }
        out
    }

    async fn read(&self, namespace: &str, key: &str) -> zbus::fdo::Result<OwnedValue> {
        let values = self.look.lock().expect("the look").values();
        match values.get(key).filter(|_| namespace == NAMESPACE) {
            Some(v) => v.try_clone().map_err(|e| zbus::fdo::Error::Failed(e.to_string())),
            None => Err(zbus::fdo::Error::UnknownProperty(format!("{namespace} {key}"))),
        }
    }

    #[zbus(signal)]
    async fn setting_changed(emitter: &SignalEmitter<'_>, namespace: &str, key: &str, value: Value<'_>) -> zbus::Result<()>;

    #[zbus(property)]
    fn version(&self) -> u32 {
        1
    }
}

fn modified() -> Option<SystemTime> {
    std::fs::metadata(gtk_css()).and_then(|m| m.modified()).ok()
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> zbus::Result<()> {
    let look = Arc::new(Mutex::new(read(&std::fs::read_to_string(gtk_css()).unwrap_or_default())));
    let conn = zbus::connection::Builder::session()?
        .name("org.freedesktop.impl.portal.desktop.vyntaris")?
        .serve_at(PATH, Settings { look: look.clone() })?
        .build()
        .await?;
    let emitter = SignalEmitter::new(&conn, PATH)?;
    let mut seen = modified();
    loop {
        tokio::time::sleep(Duration::from_secs(1)).await;
        let now = modified();
        if now == seen {
            continue;
        }
        seen = now;
        let Ok(css) = std::fs::read_to_string(gtk_css()) else { continue };
        let new = read(&css);
        let old = std::mem::replace(&mut *look.lock().expect("the look"), new);
        if new.accent != old.accent {
            Settings::setting_changed(&emitter, NAMESPACE, "accent-color", Value::from(new.accent)).await?;
        }
        if new.scheme != old.scheme {
            Settings::setting_changed(&emitter, NAMESPACE, "color-scheme", Value::from(new.scheme)).await?;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_look_from_the_shells_css() {
        let css = "/* generated */\n@define-color accent_bg_color #a6e3a1;\n@define-color window_bg_color #1e1e2e;\n";
        let l = read(css);
        assert_eq!(l.scheme, 1);
        assert!((l.accent.1 - 0xe3 as f64 / 255.0).abs() < 1e-9);
        assert_eq!(read("@define-color window_bg_color #eff1f5;").scheme, 2);
        assert_eq!(read("").scheme, 1);
    }

    #[test]
    fn namespaces_asked_for() {
        assert!(wanted(&[]));
        assert!(wanted(&["org.freedesktop.*".into()]));
        assert!(wanted(&["org.freedesktop.appearance".into()]));
        assert!(!wanted(&["org.gnome.*".into()]));
    }
}
