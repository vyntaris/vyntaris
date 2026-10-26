use std::collections::HashMap;
use std::sync::OnceLock;

static DICT: OnceLock<HashMap<String, String>> = OnceLock::new();

pub fn lang() -> String {
    let locale = ["VYNTARIS_LANG", "LC_MESSAGES", "LANG"]
        .iter()
        .find_map(|v| std::env::var(v).ok().filter(|s| !s.is_empty()))
        .unwrap_or_default();
    let l = locale.split(['_', '.', '@']).next().unwrap_or("").to_lowercase();
    if l.is_empty() || l == "c" || l == "posix" { "en".into() } else { l }
}

fn dict() -> &'static HashMap<String, String> {
    DICT.get_or_init(|| {
        let l = lang();
        if l == "en" {
            return HashMap::new();
        }
        let path = crate::paths::shell_dir().join("i18n").join(format!("{l}.json"));
        std::fs::read_to_string(path).ok().and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default()
    })
}

pub fn tr(s: &str) -> String {
    dict().get(s).filter(|t| !t.is_empty()).cloned().unwrap_or_else(|| s.to_string())
}

pub fn english() {
    let _ = DICT.set(HashMap::new());
}

#[macro_export]
macro_rules! trf {
    ($s:expr $(, $a:expr)* $(,)?) => {{
        #[allow(unused_mut)]
        let mut out = $crate::i18n::tr($s);
        #[allow(unused_mut, unused_variables)]
        let mut i = 0;
        $(
            out = out.replace(&format!("{{{}}}", i), &$a.to_string());
            i += 1;
        )*
        out
    }};
}

#[cfg(test)]
mod tests {
    #[test]
    fn english_as_written_with_its_values() {
        super::english();
        assert_eq!(super::tr("Disk health"), "Disk health");
        assert_eq!(crate::trf!("{0} of {1}", 3, "5"), "3 of 5");
        assert_eq!(crate::trf!("{1} before {0}", "b", "a"), "a before b");
    }
}
