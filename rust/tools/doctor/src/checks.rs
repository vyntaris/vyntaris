use crate::sys::{Sys, read_seen};
use regex::Regex;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;
use vyntaris_core::i18n::tr;
use vyntaris_core::trf;

pub const GB: f64 = 1024.0 * 1024.0 * 1024.0;
pub const MB: f64 = 1024.0 * 1024.0;
pub const STATE: &str = "/var/lib/vyntaris";
pub const LEVELS: &[&str] = &["error", "warn", "info", "ok", "tool"];

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/".into()))
}

pub fn size(n: f64) -> String {
    let mut n = n;
    for unit in ["B", "KB", "MB", "GB", "TB"] {
        if n < 1024.0 || unit == "TB" {
            return if unit == "B" || unit == "KB" {
                format!("{n:.0} {unit}")
            } else {
                format!("{n:.1} {unit}")
            };
        }
        n /= 1024.0;
    }
    unreachable!()
}

pub fn folder_size(path: &Path) -> f64 {
    let mut total = 0u64;
    let mut stack = vec![path.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for e in fs::read_dir(&dir).into_iter().flatten().flatten() {
            let Ok(meta) = fs::symlink_metadata(e.path()) else {
                continue;
            };
            if meta.is_dir() {
                stack.push(e.path());
            } else {
                total += meta.size();
            }
        }
    }
    total as f64
}

fn pct(share: f64) -> String {
    format!("{:.0}%", share * 100.0)
}

pub fn option(label: &str, id: Option<&str>, admin: bool, action: Option<&str>) -> Value {
    json!({ "id": id, "label": label, "admin": admin, "action": action })
}

pub struct Fix<'a> {
    pub label: &'a str,
    pub admin: bool,
    pub action: Option<&'a str>,
}

pub fn finding(
    id: &str,
    level: &str,
    title: &str,
    detail: &str,
    fix: Option<Fix>,
    more: Vec<Value>,
) -> Value {
    let mut fixes: Vec<Value> = fix
        .map(|f| vec![option(f.label, None, f.admin, f.action)])
        .unwrap_or_default();
    fixes.extend(more);
    for f in &mut fixes {
        if f["id"].is_null() {
            f["id"] = json!(id);
        }
    }
    json!({ "id": id, "level": level, "title": title, "detail": detail, "fixes": fixes })
}

fn fix(label: &str) -> Option<Fix<'_>> {
    Some(Fix {
        label,
        admin: false,
        action: None,
    })
}
fn admin(label: &str) -> Option<Fix<'_>> {
    Some(Fix {
        label,
        admin: true,
        action: None,
    })
}
fn act<'a>(label: &'a str, action: &'a str) -> Option<Fix<'a>> {
    Some(Fix {
        label,
        admin: false,
        action: Some(action),
    })
}

pub type Check = fn(&dyn Sys) -> Vec<Value>;
pub const CHECKS: &[Check] = &[
    disk_space,
    journal_size,
    thumbnails,
    services,
    crashes,
    updates,
    restart_needed,
    pacman_lock,
    pacnew,
    orphans,
    arch_news,
    log_errors,
    outdated_programs,
    dropped_packages,
    firmware,
    mirrors,
    testing_repos,
    dead_links,
    app_caches,
    disk_errors,
    time_sync,
    network_manager,
    battery,
    temperature,
    safe_updates,
    package_cache,
    trim,
    scrub,
];

fn statvfs(path: &Path) -> Option<(f64, f64)> {
    let c = std::ffi::CString::new(path.to_string_lossy().as_bytes()).ok()?;
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    (unsafe { libc::statvfs(c.as_ptr(), &mut st) } == 0).then_some((
        st.f_bavail as f64 * st.f_frsize as f64,
        st.f_blocks as f64 * st.f_frsize as f64,
    ))
}

pub fn disk_space(sys: &dyn Sys) -> Vec<Value> {
    let mut out = Vec::new();
    let mut seen = BTreeSet::new();
    for (path, name) in [(PathBuf::from("/"), &tr("Disk")), (home(), &tr("Your home's disk"))] {
        let Some((free, total)) = statvfs(&path) else {
            continue;
        };
        let (_, uuid) = sys.run(&[
            "findmnt",
            "-no",
            "UUID",
            "--target",
            &path.to_string_lossy(),
        ]);
        let fs_id = if uuid.trim().is_empty() {
            path.to_string_lossy().to_string()
        } else {
            uuid.trim().to_string()
        };
        if !seen.insert(fs_id) {
            continue;
        }
        let share = if total > 0.0 { free / total } else { 1.0 };
        let title = trf!("{0}: {1} free", name, size(free));
        let id = if path == Path::new("/") {
            "disk-root"
        } else {
            "disk-home"
        };
        out.push(if share < 0.05 || free < 2.0 * GB {
            finding(
                id,
                "error",
                &title,
                "It's almost full. Programs can stop working and updates can fail halfway. \
                Deleting files you don't need helps most; the clean-up below frees some too.",
                None,
                vec![],
            )
        } else if share < 0.12 {
            finding(
                id,
                "warn",
                &title,
                &trf!("Only {0} is left. Updates and snapshots need room.", pct(share)),
                None,
                vec![],
            )
        } else {
            finding(
                id,
                "ok",
                &title,
                &trf!("{0} of it is free.", pct(share)),
                None,
                vec![],
            )
        });
    }
    out
}

pub fn journal_size(_: &dyn Sys) -> Vec<Value> {
    let n = folder_size(Path::new("/var/log/journal"));
    if n < 250.0 * MB {
        return vec![];
    }
    vec![finding(
        "journal",
        if n > GB { "info" } else { "tool" },
        &trf!("System logs: {0}", size(n)),
        &tr("The system's logs have grown large. The last few hundred megabytes are plenty."),
        admin(&tr("Trim to 200 MB")),
        vec![],
    )]
}

pub fn thumbnails(_: &dyn Sys) -> Vec<Value> {
    let n = folder_size(&home().join(".cache/thumbnails"));
    if n < 20.0 * MB {
        return vec![];
    }
    vec![finding(
        "thumbnails",
        if n > GB { "info" } else { "tool" },
        &trf!("Picture previews: {0}", size(n)),
        &tr("Previews of pictures and videos, made again when needed."),
        fix(&tr("Clear them")),
        vec![],
    )]
}

pub fn failed_units(sys: &dyn Sys, user: bool) -> Vec<(String, String)> {
    let mut cmd = vec!["systemctl"];
    if user {
        cmd.push("--user");
    }
    cmd.extend(["--failed", "--no-legend", "--plain", "--full"]);
    static UNIT: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^[\w@.:\\-]+\.(service|socket|timer|mount|path)$").unwrap());
    let (_, out) = sys.run(&cmd);
    out.lines()
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            let unit = parts.first().filter(|u| UNIT.is_match(u))?;
            let desc = parts
                .get(4..)
                .map(|d| d.join(" "))
                .filter(|d| !d.is_empty())
                .unwrap_or_else(|| unit.to_string());
            Some((unit.to_string(), desc))
        })
        .collect()
}

pub fn services(sys: &dyn Sys) -> Vec<Value> {
    let mut out = Vec::new();
    for user in [false, true] {
        for (unit, desc) in failed_units(sys, user) {
            let id = format!("{}{unit}", if user { "user-service:" } else { "service:" });
            out.push(finding(
                &id,
                "error",
                &trf!("{0} stopped working", desc),
                &trf!("{0}'s service {1} failed and isn't running.", if user { tr("Your session") } else { tr("The system") }, unit),
                Some(Fix {
                    label: &tr("Start it again"),
                    admin: !user,
                    action: None,
                }),
                vec![],
            ));
        }
    }
    if out.is_empty() {
        out.push(finding(
            "services",
            "ok",
            &tr("Services: all running"),
            &tr("None of the system's or the session's services failed."),
            None,
            vec![],
        ));
    }
    out
}

pub fn pending_updates(sys: &dyn Sys) -> Vec<String> {
    let (code, out) = sys.run(&["checkupdates"]);
    if code != 0 {
        return vec![];
    }
    out.lines()
        .filter_map(|l| l.split_whitespace().next().map(str::to_string))
        .collect()
}

fn owner(sys: &dyn Sys, path: &str) -> String {
    let (code, out) = sys.run(&["pacman", "-Qqo", path]);
    if code == 0 {
        out.trim().to_string()
    } else {
        String::new()
    }
}

pub fn crashes(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&[
        "coredumpctl",
        "list",
        "--since=-7d",
        "--json=short",
        "--no-pager",
    ]);
    let dumps: Vec<Value> = if code == 0 {
        serde_json::from_str(&out).unwrap_or_default()
    } else {
        vec![]
    };
    let uid = unsafe { libc::getuid() } as u64;
    let seen = sys.crashes_seen();
    let mut by: BTreeMap<String, usize> = BTreeMap::new();
    let mut exes: BTreeMap<String, String> = BTreeMap::new();
    let mut order: Vec<String> = Vec::new();
    for d in &dumps {
        let du = d.get("uid").and_then(Value::as_u64);
        let time = d.get("time").and_then(Value::as_u64).unwrap_or(u64::MAX);
        if (du == Some(0) || du == Some(uid)) && time > seen {
            let exe = d
                .get("exe")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .to_string();
            let name = Path::new(&exe)
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or("?".into());
            if !by.contains_key(&name) {
                order.push(name.clone());
            }
            *by.entry(name.clone()).or_default() += 1;
            exes.insert(name, exe);
        }
    }
    if by.is_empty() {
        return vec![finding(
            "crashes",
            "ok",
            &tr("No crashes this week"),
            &tr("No program has crashed in the last seven days."),
            None,
            vec![],
        )];
    }
    let mut worst: Vec<(String, usize)> = order.iter().map(|n| (n.clone(), by[n])).collect();
    worst.sort_by_key(|w| std::cmp::Reverse(w.1));
    let names = worst
        .iter()
        .take(4)
        .map(|(n, c)| format!("{n} ({c}×)"))
        .collect::<Vec<_>>()
        .join(", ");
    let total: usize = by.values().sum();
    let title = if total == 1 { tr("1 crash this week") } else { trf!("{0} crashes this week", total) };
    let level = if total >= 5 { "warn" } else { "info" };
    let seen_opt = option(&tr("Mark as seen"), None, false, None);
    let waiting: BTreeSet<String> = pending_updates(sys).into_iter().collect();
    let fixed_by: BTreeSet<String> = exes
        .values()
        .filter(|e| !e.is_empty())
        .map(|e| owner(sys, e))
        .filter(|p| waiting.contains(p))
        .collect();
    if !fixed_by.is_empty() {
        return vec![finding(
            "crashes",
            level,
            &title,
            &trf!("These programs closed unexpectedly: {0}. An update waits for {1}, and updates often fix just that.", names, fixed_by.iter().cloned().collect::<Vec<_>>().join(", ")),
            act(&tr("Update"), "updates"),
            vec![seen_opt],
        )];
    }
    vec![finding(
        "crashes",
        level,
        &title,
        &trf!("These programs closed unexpectedly: {0}. Once is nothing to worry about; marked as seen, only new crashes count, so one that keeps doing it shows up again.", names),
        None,
        vec![seen_opt],
    )]
}

pub fn updates(sys: &dyn Sys) -> Vec<Value> {
    let Some(when) = sys.last_upgrade() else {
        return vec![];
    };
    let days = ((sys.now() - when) / 86400.0).floor() as i64;
    let waiting = pending_updates(sys).len();
    let ago = if days < 1 {
        tr("today")
    } else if days == 1 {
        tr("1 day ago")
    } else {
        trf!("{0} days ago", days)
    };
    if days >= 30 {
        return vec![finding(
            "updates-old",
            "warn",
            &trf!("Last updated {0} days ago", days),
            &tr("Updates bring security fixes. With safe updates on, an update that goes wrong undoes itself."),
            act(&tr("Update"), "updates"),
            vec![],
        )];
    }
    if waiting > 0 {
        return vec![finding(
            "updates-old",
            "info",
            &if waiting == 1 { tr("1 update waiting") } else { trf!("{0} updates waiting", waiting) },
            &trf!("Last updated {0}. With safe updates on, an update that goes wrong undoes itself.", ago),
            act(&tr("Update"), "updates"),
            vec![],
        )];
    }
    vec![finding(
        "updates-old",
        "ok",
        &tr("Up to date"),
        &trf!("Nothing waits; last updated {0}.", ago),
        None,
        vec![],
    )]
}

fn kernel_release() -> String {
    let mut u: libc::utsname = unsafe { std::mem::zeroed() };
    unsafe { libc::uname(&mut u) };
    unsafe { std::ffi::CStr::from_ptr(u.release.as_ptr()) }
        .to_string_lossy()
        .to_string()
}

pub fn kernel_there() -> bool {
    Path::new(&format!("/usr/lib/modules/{}", kernel_release())).is_dir()
}

pub fn restart_needed(_: &dyn Sys) -> Vec<Value> {
    if kernel_there() {
        return vec![];
    }
    vec![finding(
        "restart",
        "warn",
        &tr("Restart to finish the update"),
        &tr("The kernel was updated: until a restart, new USB devices and some drivers may not work."),
        act(&tr("Restart"), "restart"),
        vec![],
    )]
}

pub fn pacman_running(sys: &dyn Sys) -> bool {
    sys.run(&["pgrep", "-x", "pacman|yay|paru|pamac|makepkg"]).0 == 0
}

pub fn pacman_lock(sys: &dyn Sys) -> Vec<Value> {
    if !Path::new("/var/lib/pacman/db.lck").exists() || pacman_running(sys) {
        return vec![];
    }
    vec![finding(
        "pacman-lock",
        "error",
        &tr("Updates are blocked"),
        &tr("An update was cut off and left its lock behind, so no update or install can start."),
        admin(&tr("Remove the lock")),
        vec![],
    )]
}

pub fn pacnew(_: &dyn Sys) -> Vec<Value> {
    let mut found = Vec::new();
    let mut stack = vec![PathBuf::from("/etc")];
    while let Some(dir) = stack.pop() {
        for e in fs::read_dir(&dir).into_iter().flatten().flatten() {
            let Ok(t) = e.file_type() else { continue };
            if t.is_dir() {
                stack.push(e.path());
            } else if e.file_name().to_string_lossy().ends_with(".pacnew") {
                found.push(e.path().to_string_lossy().to_string());
            }
        }
    }
    if found.is_empty() {
        return vec![];
    }
    found.sort();
    let shown = found
        .iter()
        .take(4)
        .map(|p| {
            p.trim_start_matches("/etc/")
                .trim_end_matches(".pacnew")
                .to_string()
        })
        .collect::<Vec<_>>()
        .join(", ");
    let n = found.len();
    vec![finding(
        "pacnew",
        "info",
        &if n == 1 { tr("1 settings file with a newer version") } else { trf!("{0} settings files with a newer version", n) },
        &trf!("An update brought new versions of {0}{1} next to the ones in use (as .pacnew). Nothing is wrong; they're there to compare when something behaves differently.", shown, if n > 4 { "…" } else { "" }),
        None,
        vec![],
    )]
}

pub fn orphans(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&["pacman", "-Qdtq"]);
    let pkgs: Vec<&str> = if code == 0 {
        out.split_whitespace().collect()
    } else {
        vec![]
    };
    if pkgs.is_empty() {
        return vec![finding(
            "orphans",
            "tool",
            &tr("Unneeded packages: none"),
            &tr("Packages that came in for programs since removed are taken out here; there are none now."),
            None,
            vec![],
        )];
    }
    vec![finding(
        "orphans",
        "tool",
        &trf!("Unneeded packages: {0}", pkgs.len()),
        &trf!("They came in for programs that are gone now: {0}{1}.", pkgs.iter().take(5).copied().collect::<Vec<_>>().join(", "), if pkgs.len() > 5 { "…" } else { "" }),
        admin(&tr("Remove them")),
        vec![],
    )]
}

pub fn rfc2822(s: &str) -> Option<f64> {
    let parts: Vec<&str> = s.split_whitespace().collect();
    let p = if parts.first()?.ends_with(',') {
        &parts[1..]
    } else {
        &parts[..]
    };
    let day: i64 = p.first()?.parse().ok()?;
    let month = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]
    .iter()
    .position(|m| p.get(1) == Some(m))? as i64
        + 1;
    let year: i64 = p.get(2)?.parse().ok()?;
    let hms: Vec<i64> = p
        .get(3)?
        .split(':')
        .filter_map(|x| x.parse().ok())
        .collect();
    let zone = p.get(4).copied().unwrap_or("+0000");
    let offset = match zone {
        "GMT" | "UT" | "UTC" | "Z" => 0,
        z if z.len() == 5 && (z.starts_with('+') || z.starts_with('-')) => {
            let v: i64 = z[1..].parse().ok()?;
            let sign = if z.starts_with('-') { -1 } else { 1 };
            sign * ((v / 100) * 3600 + (v % 100) * 60)
        }
        _ => 0,
    };
    let (y, m) = if month <= 2 {
        (year - 1, month + 9)
    } else {
        (year, month - 3)
    };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(
        (days * 86400 + hms.first()? * 3600 + hms.get(1)? * 60 + hms.get(2).copied().unwrap_or(0)
            - offset) as f64,
    )
}

pub fn news_since(rss: &str, since: f64) -> Vec<(String, String)> {
    let Ok(doc) = roxmltree::Document::parse(rss) else {
        return vec![];
    };
    let text = |n: roxmltree::Node, tag: &str| {
        n.children()
            .find(|c| c.has_tag_name(tag))
            .and_then(|c| c.text())
            .unwrap_or("")
            .trim()
            .to_string()
    };
    doc.descendants()
        .filter(|n| n.has_tag_name("item"))
        .filter_map(|item| {
            let when = rfc2822(&text(item, "pubDate"))?;
            (when > since).then(|| (text(item, "title"), text(item, "link")))
        })
        .collect()
}

pub fn arch_news(sys: &dyn Sys) -> Vec<Value> {
    let Some(when) = sys.last_upgrade() else {
        return vec![];
    };
    let Some(rss) = sys.fetch("https://archlinux.org/feeds/news/") else {
        return vec![];
    };
    let news = news_since(&rss, when);
    let Some((title, link)) = news.first() else {
        return vec![];
    };
    let more = if news.len() > 1 {
        trf!(" (and {0} more)", news.len() - 1)
    } else {
        String::new()
    };
    let action = format!("open:{link}");
    vec![finding(
        "arch-news",
        "warn",
        &tr("Arch news to read before updating"),
        &trf!("“{0}”{1}: some updates need a step of your own, and the news says which.", title, more),
        act(&tr("Read it"), &action),
        vec![],
    )]
}

pub static HARMLESS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
    r"(?i)ACPI (BIOS )?Error|ACPI Error|AE_NOT_FOUND|firmware bug|Firmware Bug|TDX not supported|gkr-pam|Failed to set mode|failed to find wayland buffer|RealtimeKit|multicast RX registrations are not supported",
).unwrap()
});

pub fn log_errors(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&[
        "journalctl",
        "-b",
        "-p",
        "err",
        "-o",
        "json",
        "--no-pager",
        "-q",
        "--output-fields=MESSAGE,SYSLOG_IDENTIFIER,__REALTIME_TIMESTAMP",
    ]);
    if code != 0 {
        return vec![];
    }
    let seen = read_seen("errors-seen");
    let mut by: Vec<(String, usize)> = Vec::new();
    for line in out.lines() {
        let Ok(e) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let msg = e.get("MESSAGE").and_then(Value::as_str).unwrap_or("");
        let t: u64 = e
            .get("__REALTIME_TIMESTAMP")
            .and_then(Value::as_str)
            .and_then(|s| s.parse().ok())
            .unwrap_or(0);
        if msg.trim().is_empty() || t <= seen || HARMLESS.is_match(msg) {
            continue;
        }
        let who = e
            .get("SYSLOG_IDENTIFIER")
            .and_then(Value::as_str)
            .unwrap_or("system")
            .to_string();
        match by.iter_mut().find(|(w, _)| *w == who) {
            Some((_, n)) => *n += 1,
            None => by.push((who, 1)),
        }
    }
    if by.is_empty() {
        return vec![finding(
            "log-errors",
            "ok",
            &tr("System log: no errors"),
            &tr("Nothing went wrong since the last start."),
            None,
            vec![],
        )];
    }
    let total: usize = by.iter().map(|(_, n)| n).sum();
    by.sort_by_key(|w| std::cmp::Reverse(w.1));
    let names = by
        .iter()
        .take(4)
        .map(|(w, n)| format!("{w} ({n})"))
        .collect::<Vec<_>>()
        .join(", ");
    vec![finding(
        "log-errors",
        "info",
        &if total == 1 { tr("1 error in the system log") } else { trf!("{0} errors in the system log", total) },
        &trf!("Since the last start, from {0}. Most are harmless; one that repeats points at what's wrong.", names),
        act(&tr("Show them"), "journal"),
        vec![option(&tr("Mark as seen"), None, false, None)],
    )]
}

pub fn deleted_libraries() -> Vec<String> {
    let uid = unsafe { libc::getuid() };
    let mut old = BTreeSet::new();
    for e in fs::read_dir("/proc").into_iter().flatten().flatten() {
        if e.file_name().to_string_lossy().parse::<u32>().is_err()
            || e.metadata().map(|m| m.uid() != uid).unwrap_or(true)
        {
            continue;
        }
        let Ok(maps) = fs::read_to_string(e.path().join("maps")) else {
            continue;
        };
        if maps
            .lines()
            .any(|l| l.contains(".so") && l.trim_end().ends_with("(deleted)"))
            && let Some(exe) = fs::read_link(e.path().join("exe"))
                .ok()
                .and_then(|p| p.file_name().map(|f| f.to_string_lossy().to_string()))
        {
            old.insert(exe);
        }
    }
    old.into_iter().collect()
}

pub fn outdated_programs(_: &dyn Sys) -> Vec<Value> {
    if !kernel_there() {
        return vec![];
    }
    let old = deleted_libraries();
    if old.is_empty() {
        return vec![];
    }
    let n = old.len();
    vec![finding(
        "outdated",
        "info",
        &if n == 1 { tr("1 program still on the old version") } else { trf!("{0} programs still on the old version", n) },
        &trf!("Updated while running, they go on with the old code until they start again: {0}{1}. A restart takes care of all of them.", old.iter().take(5).cloned().collect::<Vec<_>>().join(", "), if n > 5 { "…" } else { "" }),
        act(&tr("Restart"), "restart"),
        vec![],
    )]
}

fn quote(s: &str) -> String {
    s.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-._~/".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}

pub fn dropped_packages(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&["pacman", "-Qmq"]);
    let foreign: Vec<&str> = if code == 0 {
        out.split_whitespace().take(150).collect()
    } else {
        vec![]
    };
    if foreign.is_empty() {
        return vec![];
    }
    let url = format!(
        "https://aur.archlinux.org/rpc/v5/info?{}",
        foreign
            .iter()
            .map(|p| format!("arg[]={}", quote(p)))
            .collect::<Vec<_>>()
            .join("&")
    );
    let Some(reply) = sys.fetch(&url) else {
        return vec![];
    };
    let Ok(v) = serde_json::from_str::<Value>(&reply) else {
        return vec![];
    };
    let known: BTreeSet<&str> = v
        .get("results")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|r| r.get("Name").and_then(Value::as_str))
        .collect();
    let gone: Vec<&str> = foreign
        .iter()
        .copied()
        .filter(|p| !known.contains(p) && !p.starts_with("vyntaris"))
        .collect();
    if gone.is_empty() {
        return vec![];
    }
    let n = gone.len();
    vec![finding(
        "dropped",
        "info",
        &if n == 1 { tr("1 package nothing offers any more") } else { trf!("{0} packages nothing offers any more", n) },
        &trf!("Neither Arch nor the AUR has {0} any more: they get no fixes. Replacing them with what took their place is safest.", gone.iter().take(5).copied().collect::<Vec<_>>().join(", ")),
        None,
        vec![],
    )]
}

pub fn firmware(sys: &dyn Sys) -> Vec<Value> {
    let (_, out) = sys.run(&[
        "fwupdmgr",
        "get-updates",
        "--json",
        "--no-unreported-check",
        "--no-metadata-check",
    ]);
    let devices: Vec<Value> = serde_json::from_str::<Value>(&out)
        .ok()
        .and_then(|v| v.get("Devices").and_then(Value::as_array).cloned())
        .unwrap_or_default()
        .into_iter()
        .filter(|d| {
            d.get("Releases")
                .and_then(Value::as_array)
                .is_some_and(|r| !r.is_empty())
        })
        .collect();
    if devices.is_empty() {
        return vec![];
    }
    let names = devices
        .iter()
        .take(3)
        .map(|d| {
            d.get("Name")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .to_string()
        })
        .collect::<Vec<_>>()
        .join(", ");
    vec![finding(
        "firmware",
        "info",
        &if devices.len() == 1 { trf!("Firmware update for {0}", names) } else { trf!("Firmware updates for {0}", names) },
        &tr("The makers of the hardware fixed something in it; the update installs at a restart."),
        act(&tr("Update"), "updates"),
        vec![],
    )]
}

pub fn mirrors(sys: &dyn Sys) -> Vec<Value> {
    let Ok(meta) = fs::metadata("/etc/pacman.d/mirrorlist") else {
        return vec![];
    };
    let age = (sys.now() - meta.mtime() as f64) / 86400.0;
    if age < 30.0 {
        return vec![];
    }
    vec![finding(
        "mirrors",
        "info",
        &trf!("The download servers were picked {0} days ago", age as i64),
        &tr("Some may have gone slow or offline since; picking the fastest again speeds up updates."),
        admin(&tr("Pick again")),
        vec![],
    )]
}

pub fn testing_repos(_: &dyn Sys) -> Vec<Value> {
    let Ok(conf) = fs::read_to_string("/etc/pacman.conf") else {
        return vec![];
    };
    static TESTING: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?m)^\[([a-z]+-testing)\]").unwrap());
    let on: Vec<String> = TESTING
        .captures_iter(&conf)
        .map(|c| c[1].to_string())
        .collect();
    if on.is_empty() {
        return vec![];
    }
    vec![finding(
        "testing",
        "warn",
        &tr("Test versions of packages are on"),
        &trf!("pacman takes packages from {0}: versions still being tried out, which can break things. Arch advises against them on a computer used day to day.", on.join(", ")),
        None,
        vec![],
    )]
}

pub fn broken_links() -> Vec<PathBuf> {
    broken_links_in(&home())
}

fn is_lock(p: &Path) -> bool {
    let name = p
        .file_name()
        .map(|n| n.to_string_lossy())
        .unwrap_or_default();
    name == "lock" || name.starts_with("Singleton")
}

pub fn broken_links_in(home: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for base in [home.join(".config"), home.join(".local/share")] {
        let mut stack = vec![(base, 0)];
        while let Some((dir, depth)) = stack.pop() {
            for e in fs::read_dir(&dir).into_iter().flatten().flatten() {
                let p = e.path();
                let Ok(meta) = fs::symlink_metadata(&p) else {
                    continue;
                };
                if meta.file_type().is_symlink() {
                    if !p.exists() && !is_lock(&p) {
                        out.push(p);
                    }
                } else if meta.is_dir() && depth < 4 {
                    stack.push((p, depth + 1));
                }
            }
        }
    }
    out
}

pub fn dead_links(_: &dyn Sys) -> Vec<Value> {
    let links = broken_links();
    if links.is_empty() {
        return vec![];
    }
    let h = home().to_string_lossy().to_string();
    let shown = links
        .iter()
        .take(3)
        .map(|l| l.to_string_lossy().replacen(&h, "~", 1))
        .collect::<Vec<_>>()
        .join(", ");
    vec![finding(
        "dead-links",
        "tool",
        &trf!("Broken links in your settings: {0}", links.len()),
        &trf!("Links to files that are gone, left by apps since removed: {0}{1}.", shown, if links.len() > 3 { "…" } else { "" }),
        fix(&tr("Remove them")),
        vec![],
    )]
}

pub const CACHE_KEEP: &[&str] = &[
    "vyntaris",
    "quickshell",
    "thumbnails",
    "mesa_shader_cache",
    "nvidia",
    "fontconfig",
    "mozilla",
];

pub fn app_caches(_: &dyn Sys) -> Vec<Value> {
    let base = home().join(".cache");
    let Ok(entries) = fs::read_dir(&base) else {
        return vec![];
    };
    let mut n = 0.0;
    for e in entries.flatten() {
        if CACHE_KEEP.contains(&e.file_name().to_string_lossy().as_ref()) {
            continue;
        }
        let Ok(meta) = fs::symlink_metadata(e.path()) else {
            continue;
        };
        if meta.file_type().is_symlink() {
            continue;
        }
        n += if meta.is_dir() {
            folder_size(&e.path())
        } else {
            meta.size() as f64
        };
    }
    if n < 300.0 * MB {
        return vec![];
    }
    vec![finding(
        "app-caches",
        "tool",
        &trf!("App caches: {0}", size(n)),
        &tr("What apps keep to start faster; they make it again when needed."),
        fix(&tr("Clear them")),
        vec![],
    )]
}

static DISK_ERRORS: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
    r"(?i)I/O error|BTRFS (error|critical)|csum failed|EXT4-fs error|critical medium error|nvme\S* .*(timeout|controller is down|failed)|ata\d+(\.\d+)?: (failed command|exception)",
).unwrap()
});

pub fn disk_errors(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&[
        "journalctl",
        "-k",
        "-b",
        "-p",
        "warning",
        "--no-pager",
        "-q",
        "-o",
        "cat",
    ]);
    if code != 0 {
        return vec![];
    }
    let errors = out.lines().filter(|l| DISK_ERRORS.is_match(l)).count();
    if errors == 0 {
        return vec![finding(
            "disk-health",
            "ok",
            &tr("Disk health: no errors"),
            &tr("The disk reported no read or write errors since the last start."),
            None,
            vec![],
        )];
    }
    vec![finding(
        "disk-health",
        "error",
        &tr("The disk reported errors"),
        &if errors == 1 { tr("1 read or write error since the last start. Disks often warn like this before they fail: copy what matters somewhere else soon.") } else { trf!("{0} read or write errors since the last start. Disks often warn like this before they fail: copy what matters somewhere else soon.", errors) },
        None,
        vec![],
    )]
}

pub fn time_sync(sys: &dyn Sys) -> Vec<Value> {
    let (code, out) = sys.run(&["timedatectl", "show", "-p", "NTP", "-p", "NTPSynchronized"]);
    if code != 0 || !out.lines().any(|l| l == "NTP=no") {
        return vec![];
    }
    vec![finding(
        "time-sync",
        "warn",
        &tr("The clock isn't set automatically"),
        &tr("A clock that drifts breaks secure websites and updates."),
        admin(&tr("Set it automatically")),
        vec![],
    )]
}

pub fn network_manager(sys: &dyn Sys) -> Vec<Value> {
    if sys
        .run(&[
            "systemctl",
            "is-active",
            "--quiet",
            "NetworkManager.service",
        ])
        .0
        == 0
    {
        return vec![];
    }
    vec![finding(
        "network",
        "error",
        &tr("Networking is off"),
        &tr("The service that connects to Wi-Fi and cable networks isn't running."),
        admin(&tr("Turn it on")),
        vec![],
    )]
}

pub fn battery(_: &dyn Sys) -> Vec<Value> {
    let mut bats: Vec<PathBuf> = fs::read_dir("/sys/class/power_supply")
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with("BAT"))
        .map(|e| e.path())
        .collect();
    bats.sort();
    let mut out = Vec::new();
    for bat in bats {
        let read = |n: &str| {
            fs::read_to_string(bat.join(n))
                .ok()
                .and_then(|s| s.trim().parse::<f64>().ok())
                .filter(|v| *v > 0.0)
        };
        let (Some(full), Some(design)) = (
            read("energy_full").or_else(|| read("charge_full")),
            read("energy_full_design").or_else(|| read("charge_full_design")),
        ) else {
            continue;
        };
        let health = full / design;
        if health < 0.6 {
            out.push(finding(
                "battery",
                "warn",
                &trf!("Battery holds {0} of what it did new", pct(health)),
                &tr("It has worn down: it runs out sooner. A new battery brings the time back."),
                None,
                vec![],
            ));
        } else if health < 0.8 {
            out.push(finding(
                "battery",
                "info",
                &trf!("Battery holds {0} of what it did new", pct(health)),
                &tr("Normal wear. Settings → Power can stop charging at 80 %, which slows it down."),
                None,
                vec![],
            ));
        }
    }
    out
}

pub fn temperature(_: &dyn Sys) -> Vec<Value> {
    let mut hottest: f64 = 0.0;
    for hw in fs::read_dir("/sys/class/hwmon")
        .into_iter()
        .flatten()
        .flatten()
    {
        let chip = fs::read_to_string(hw.path().join("name"))
            .unwrap_or_default()
            .trim()
            .to_string();
        for e in fs::read_dir(hw.path()).into_iter().flatten().flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if !(name.starts_with("temp") && name.ends_with("_input")) {
                continue;
            }
            let label = fs::read_to_string(hw.path().join(name.replace("_input", "_label")))
                .unwrap_or_default()
                .trim()
                .to_lowercase();
            if !["k10temp", "coretemp", "zenpower", "cpu_thermal"].contains(&chip.as_str())
                && !label.contains("package")
            {
                continue;
            }
            if let Some(t) = fs::read_to_string(e.path())
                .ok()
                .and_then(|s| s.trim().parse::<f64>().ok())
            {
                hottest = hottest.max(t / 1000.0);
            }
        }
    }
    if hottest < 90.0 {
        return vec![];
    }
    vec![finding(
        "temperature",
        "warn",
        &trf!("The processor is at {0} °C", format!("{:.0}", hottest)),
        &tr("That's hot. Dust in the fan or a blocked vent is the usual cause; heavy work makes it hot too."),
        None,
        vec![],
    )]
}

pub fn safe_updates(_: &dyn Sys) -> Vec<Value> {
    let Some(s) = fs::read_to_string(Path::new(STATE).join("update-guard.json"))
        .ok()
        .and_then(|s| serde_json::from_str::<Value>(&s).ok())
    else {
        return vec![];
    };
    if s.get("protected").and_then(Value::as_bool).unwrap_or(false) {
        return vec![finding(
            "safe-updates",
            "ok",
            &tr("Safe updates: on"),
            &tr("If an update keeps Vyntaris from starting, it undoes itself."),
            None,
            vec![],
        )];
    }
    let reason = s.get("reason").and_then(Value::as_str).unwrap_or("unknown");
    vec![finding(
        "safe-updates",
        "info",
        &tr("Safe updates: off"),
        &trf!("An update that keeps Vyntaris from starting can't undo itself here ({0}). Snapshots are still taken before updates.", reason),
        None,
        vec![],
    )]
}

pub const PKG_CACHE: &str = "/var/cache/pacman/pkg";

pub fn package_cache(_: &dyn Sys) -> Vec<Value> {
    let n = folder_size(Path::new(PKG_CACHE));
    if n < GB {
        return vec![];
    }
    vec![finding(
        "pkg-cache",
        if n > 5.0 * GB { "info" } else { "tool" },
        &trf!("Downloaded packages: {0}", size(n)),
        &tr("Every version of every package downloaded. Keeping only the installed ones frees most of it; going back to an older version would download it again."),
        admin(&tr("Keep the installed ones")),
        vec![],
    )]
}

pub fn trim(sys: &dyn Sys) -> Vec<Value> {
    let (_, rota) = sys.run(&["lsblk", "-dno", "ROTA,TYPE"]);
    let ssd = rota.lines().any(|l| {
        let f: Vec<&str> = l.split_whitespace().collect();
        f == ["0", "disk"]
    });
    if !ssd
        || sys
            .run(&["systemctl", "is-enabled", "--quiet", "fstrim.timer"])
            .0
            == 0
    {
        return vec![];
    }
    vec![finding(
        "trim",
        "warn",
        &tr("Your SSD isn't trimmed"),
        &tr("An SSD needs to be told which space is free, weekly, or it gets slower and wears out sooner."),
        admin(&tr("Trim it every week")),
        vec![],
    )]
}

pub fn scrub(sys: &dyn Sys) -> Vec<Value> {
    let (_, fs) = sys.run(&["findmnt", "-no", "FSTYPE", "/"]);
    if fs.trim() != "btrfs"
        || sys
            .run(&["systemctl", "is-enabled", "--quiet", "btrfs-scrub@-.timer"])
            .0
            == 0
    {
        return vec![];
    }
    vec![finding(
        "scrub",
        "info",
        &tr("The disk isn't checked for damage"),
        &tr("Btrfs can read everything through once a month and catch damage before it spreads."),
        admin(&tr("Check it every month")),
        vec![],
    )]
}
