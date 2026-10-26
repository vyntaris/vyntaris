use crate::checks::HARMLESS;
use crate::sys::Sys;
use regex::Regex;
use serde_json::{Value, json};
use std::fs;
use std::path::Path;
use std::sync::LazyLock;

pub const ISSUES: &str = "https://github.com/vyntaris/vyntaris/issues";
pub const URL_BUDGET: usize = 7600;

fn os_release() -> Vec<(String, String)> {
    fs::read_to_string("/etc/os-release")
        .unwrap_or_default()
        .lines()
        .filter_map(|l| {
            l.split_once('=')
                .map(|(k, v)| (k.to_string(), v.trim_matches('"').to_string()))
        })
        .collect()
}

fn release(key: &str) -> String {
    os_release()
        .into_iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v)
        .unwrap_or_default()
}

fn nodename() -> String {
    let mut u: libc::utsname = unsafe { std::mem::zeroed() };
    unsafe { libc::uname(&mut u) };
    unsafe { std::ffi::CStr::from_ptr(u.nodename.as_ptr()) }
        .to_string_lossy()
        .to_string()
}

pub fn private_words(sys: &dyn Sys) -> Vec<String> {
    let mut words: Vec<String> = vec![std::env::var("USER").unwrap_or_default(), nodename()];
    let pw = unsafe { libc::getpwuid(libc::getuid()) };
    if !pw.is_null() {
        let s = |p: *const libc::c_char| {
            if p.is_null() {
                String::new()
            } else {
                unsafe { std::ffi::CStr::from_ptr(p) }
                    .to_string_lossy()
                    .to_string()
            }
        };
        words.push(s(unsafe { (*pw).pw_name }));
        words.extend(
            s(unsafe { (*pw).pw_gecos })
                .split(|c: char| c == ',' || c.is_whitespace())
                .filter(|w| w.chars().count() > 2)
                .map(str::to_string),
        );
    }
    let (code, out) = sys.run(&["nmcli", "-t", "-f", "NAME", "connection", "show"]);
    if code == 0 {
        words.extend(out.lines().map(|l| l.trim().to_string()));
    }
    let common = [
        "lo",
        "root",
        "localhost",
        "vyntaris",
        "arch",
        "archlinux",
        "linux",
    ];
    let id = release("ID");
    let mut words: Vec<String> = words
        .into_iter()
        .filter(|w| {
            w.chars().count() > 2
                && !common.contains(&w.to_lowercase().as_str())
                && w.to_lowercase() != id
        })
        .collect();
    words.sort_by_key(|w| std::cmp::Reverse(w.chars().count()));
    words.dedup();
    words
}

fn word_char(c: char) -> bool {
    c.is_alphanumeric() || c == '_' || c == '-'
}

fn hide_word(text: &str, word: &str) -> String {
    let Ok(re) = Regex::new(&format!("(?i){}", regex::escape(word))) else {
        return text.into();
    };
    let mut out = String::new();
    let mut last = 0;
    for m in re.find_iter(text) {
        let before = text[..m.start()].chars().next_back();
        let after = text[m.end()..].chars().next();
        if before.is_some_and(word_char) || after.is_some_and(word_char) {
            continue;
        }
        out.push_str(&text[last..m.start()]);
        out.push_str("[name]");
        last = m.end();
    }
    out.push_str(&text[last..]);
    out
}

pub fn redact(text: &str, words: &[String]) -> String {
    static EMAIL: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"[\w.+-]+@[\w-]+\.[\w.-]+").unwrap());
    static MAC: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)\b(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}\b").unwrap());
    static IP4: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"\b(?:\d{1,3}\.){3}\d{1,3}\b").unwrap());
    static IP6: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)\b(?:[0-9a-f]{1,4}:){3,7}[0-9a-f]{1,4}\b").unwrap());
    static SERIAL: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)(serial(?: ?number)?[\s:=]+)\S+").unwrap());
    let mut t = text.to_string();
    let home = std::env::var("HOME").unwrap_or_default();
    if !home.is_empty() && home != "/" {
        t = t.replace(&home, "~");
    }
    for w in words {
        t = hide_word(&t, w);
    }
    t = EMAIL.replace_all(&t, "[email]").into_owned();
    t = MAC.replace_all(&t, "[mac]").into_owned();
    t = IP4.replace_all(&t, "[ip]").into_owned();
    t = IP6.replace_all(&t, "[ip]").into_owned();
    SERIAL.replace_all(&t, "${1}[serial]").into_owned()
}

fn tail(path: &Path, n: usize) -> Vec<String> {
    let Ok(b) = fs::read(path) else { return vec![] };
    let text = String::from_utf8_lossy(&b);
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(n)..]
        .iter()
        .map(|l| l.trim_end().to_string())
        .collect()
}

pub fn unique_last(lines: &[String], n: usize) -> Vec<String> {
    static DIGITS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d+").unwrap());
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    for l in lines.iter().rev() {
        if !l.trim().is_empty() && seen.insert(DIGITS.replace_all(l, "#").into_owned()) {
            out.push(l.clone());
        }
        if out.len() >= n {
            break;
        }
    }
    out.reverse();
    out
}

pub type Section = (String, Vec<String>, usize);

pub fn sections(sys: &dyn Sys, findings: &[Value]) -> Vec<Section> {
    let (_, hypr) = sys.run(&["Hyprland", "--version"]);
    let hypr = if hypr.starts_with("Hyprland") {
        hypr.split_whitespace().nth(1).unwrap_or("?").to_string()
    } else {
        hypr.trim().chars().take(40).collect()
    };
    let (_, qs) = sys.run(&["qs", "--version"]);
    let qs = qs
        .lines()
        .next()
        .unwrap_or("")
        .trim_start_matches("Quickshell")
        .trim()
        .split(" (")
        .next()
        .unwrap_or("")
        .to_string();
    let (_, gpus) = sys.run(&[
        "sh",
        "-c",
        "lspci | grep -iE 'vga|3d|display' | cut -d: -f3-",
    ]);
    let meminfo = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let mem = meminfo
        .lines()
        .find(|l| l.starts_with("MemTotal"))
        .and_then(|l| l.split_whitespace().nth(1)?.parse::<f64>().ok())
        .map(|kb| format!("{:.0} GB", kb / 1024.0 / 1024.0))
        .unwrap_or_default();
    let cpu = fs::read_to_string("/proc/cpuinfo")
        .unwrap_or_default()
        .lines()
        .find(|l| l.starts_with("model name"))
        .and_then(|l| l.split_once(':'))
        .map(|(_, v)| v.trim().to_string())
        .unwrap_or_default();
    let mut u: libc::utsname = unsafe { std::mem::zeroed() };
    unsafe { libc::uname(&mut u) };
    let kernel = unsafe { std::ffi::CStr::from_ptr(u.release.as_ptr()) }
        .to_string_lossy()
        .to_string();
    let mut system = vec![
        format!("Vyntaris {}, kernel {kernel}", {
            let v = release("VERSION_ID");
            if v.is_empty() { "?".into() } else { v }
        }),
        format!(
            "Hyprland {hypr}, Quickshell {}",
            qs.chars().take(30).collect::<String>()
        ),
        format!("{cpu}, {mem} RAM"),
    ];
    system.extend(
        gpus.lines()
            .map(str::trim)
            .filter(|g| !g.is_empty())
            .map(str::to_string),
    );

    let found: Vec<String> = findings
        .iter()
        .filter(|f| matches!(f["level"].as_str(), Some("error" | "warn" | "info")))
        .map(|f| {
            format!(
                "- [{}] {}: {}",
                f["level"].as_str().unwrap_or(""),
                f["title"].as_str().unwrap_or(""),
                f["detail"].as_str().unwrap_or("")
            )
        })
        .collect();

    let (_, errs) = sys.run(&[
        "journalctl",
        "-b",
        "-p",
        "err",
        "-o",
        "json",
        "--no-pager",
        "-q",
        "-n",
        "300",
        "--output-fields=MESSAGE,SYSLOG_IDENTIFIER",
    ]);
    let lines: Vec<String> = errs
        .lines()
        .filter_map(|raw| {
            let e: Value = serde_json::from_str(raw).ok()?;
            let msg = e
                .get("MESSAGE")
                .and_then(Value::as_str)?
                .trim()
                .lines()
                .next()?
                .to_string();
            (!msg.is_empty() && !HARMLESS.is_match(&msg)).then(|| {
                format!(
                    "{}: {}",
                    e.get("SYSLOG_IDENTIFIER")
                        .and_then(Value::as_str)
                        .unwrap_or("system"),
                    msg.chars().take(200).collect::<String>()
                )
            })
        })
        .collect();
    let errors = unique_last(&lines, 25);
    let (_, shell) = sys.run(&[
        "journalctl",
        "--user",
        "-b",
        "-u",
        "vyntaris-shell",
        "-p",
        "warning",
        "-o",
        "cat",
        "--no-pager",
        "-q",
        "-n",
        "300",
    ]);
    let shell = unique_last(&shell.lines().map(str::to_string).collect::<Vec<_>>(), 20);

    static NOISE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"^>|xkbcomp|XKEYBOARD|Errors from xkbcomp|^\s*$|Creating the \w+!|DEBUG|^\s+[A-Za-z]+(\s+[A-Za-z]+)*\s*$").unwrap()
    });
    static ANSI: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\x1b\[[0-9;]*m").unwrap());
    let session: Vec<String> = tail(
        &vyntaris_core::paths::state_home().join("vyntaris/session.log"),
        300,
    )
    .iter()
    .map(|l| ANSI.replace_all(l, "").into_owned())
    .filter(|l| !NOISE.is_match(l))
    .collect();
    let session = unique_last(&session, 20);

    let (_, dumps) = sys.run(&["coredumpctl", "list", "--since=-7d", "--no-pager", "-q"]);
    let dumps: Vec<String> = dumps
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(str::to_string)
        .collect();
    let dumps = dumps[dumps.len().saturating_sub(8)..].to_vec();

    let mut reports: Vec<_> = fs::read_dir(crate::checks::home().join(".cache/hyprland"))
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            e.file_name()
                .to_string_lossy()
                .starts_with("hyprlandCrashReport")
        })
        .collect();
    reports.sort_by_key(|e| e.metadata().and_then(|m| m.modified()).ok());
    let crash = reports
        .last()
        .map(|r| {
            let lines = tail(&r.path(), 400);
            let at = lines.iter().position(|l| l.contains("signal")).unwrap_or(0);
            lines[at..]
                .iter()
                .take(40)
                .filter(|l| !l.trim().is_empty())
                .take(25)
                .cloned()
                .collect()
        })
        .unwrap_or_default();

    let n = system.len();
    vec![
        ("System".into(), system, n),
        ("What Dr. Help found".into(), found, 3),
        ("Errors since the start".into(), errors, 5),
        ("The shell's warnings".into(), shell, 4),
        ("The session's log, its end".into(), session, 4),
        ("Crashes this week".into(), dumps, 2),
        ("Hyprland's last crash report".into(), crash, 6),
    ]
}

pub fn form_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b' ' => "+".to_string(),
            b if b.is_ascii_alphanumeric() || b"_.-~".contains(&b) => (b as char).to_string(),
            b => format!("%{b:02X}"),
        })
        .collect()
}

pub fn report(description: &str, words: &[String], sections: Vec<Section>) -> Value {
    let mut description = redact(description.trim(), words);
    if description.is_empty() {
        description = "(nothing written)".into();
    }
    let first = description.lines().next().unwrap_or("").to_string();
    let title = format!(
        "Problem: {}",
        if first.chars().count() > 70 {
            format!("{}…", first.chars().take(70).collect::<String>())
        } else {
            first
        }
    );
    let mut secs: Vec<Section> = sections
        .into_iter()
        .map(|(h, lines, least)| (h, lines.iter().map(|l| redact(l, words)).collect(), least))
        .collect();
    let body_of = |description: &str, secs: &[Section]| {
        let mut parts = vec![
            "### What went wrong".to_string(),
            description.to_string(),
            String::new(),
            "<sub>Sent from Dr. Help. Names, networks and addresses are taken out.</sub>".into(),
            String::new(),
        ];
        for (h, lines, _) in secs {
            if lines.is_empty() {
                continue;
            }
            let fence = h != "What Dr. Help found";
            parts.push(format!("### {h}"));
            if fence {
                parts.push("```".into());
            }
            parts.extend(lines.iter().cloned());
            if fence {
                parts.push("```".into());
            }
            parts.push(String::new());
        }
        parts.join("\n")
    };
    let url_of = |body: &str| {
        format!(
            "{ISSUES}/new?title={}&body={}&labels=bug",
            form_encode(&title),
            form_encode(body)
        )
    };
    let mut url = url_of(&body_of(&description, &secs));
    while url.len() > URL_BUDGET {
        let i = secs
            .iter()
            .rposition(|s| s.1.len() > s.2)
            .or_else(|| secs.iter().rposition(|s| !s.1.is_empty()));
        let Some(i) = i else { break };
        secs[i].1.remove(0);
        url = url_of(&body_of(&description, &secs));
    }
    while url.len() > URL_BUDGET && description.chars().count() > 200 {
        let keep = description.chars().count() * 8 / 10;
        description = format!(
            "{}…",
            description
                .chars()
                .take(keep)
                .collect::<String>()
                .trim_end()
        );
        url = url_of(&body_of(&description, &secs));
    }
    json!({ "title": title, "body": body_of(&description, &secs), "url": url })
}
