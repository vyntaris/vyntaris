use crate::checks::*;
use crate::fixes;
use crate::report::{self, ISSUES, URL_BUDGET};
use crate::sys::Sys;
use serde_json::{Value, json};
use std::cell::RefCell;

#[derive(Default)]
struct Fake {
    answers: Vec<(&'static str, (i32, String))>,
    fetched: RefCell<Option<String>>,
    seen: u64,
    last_upgrade: Option<f64>,
    now: f64,
}

impl Sys for Fake {
    fn run(&self, cmd: &[&str]) -> (i32, String) {
        let line = cmd.join(" ");
        self.answers
            .iter()
            .find(|(k, _)| line.contains(k))
            .map(|(_, v)| v.clone())
            .unwrap_or((127, String::new()))
    }
    fn fetch(&self, _: &str) -> Option<String> {
        self.fetched.borrow().clone()
    }
    fn crashes_seen(&self) -> u64 {
        self.seen
    }
    fn last_upgrade(&self) -> Option<f64> {
        self.last_upgrade
    }
    fn now(&self) -> f64 {
        self.now
    }
    fn private_words(&self) -> Vec<String> {
        vec![]
    }
}

fn says(answers: &[(&'static str, (i32, &str))]) -> Fake {
    vyntaris_core::i18n::english();
    Fake {
        answers: answers
            .iter()
            .map(|(k, (c, o))| (*k, (*c, o.to_string())))
            .collect(),
        now: 2.0e9,
        ..Default::default()
    }
}

fn labels(f: &Value) -> Vec<&str> {
    f["fixes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["label"].as_str().unwrap())
        .collect()
}

#[test]
fn the_kernels_log() {
    let noise = "ACPI BIOS Error (bug): Could not resolve symbol [\\_SB.PCI0.PB2], AE_NOT_FOUND\nvirt/tdx: TDX not supported by the host platform\nBluetooth: hci0: Failed to set mode";
    assert_eq!(
        disk_errors(&says(&[("journalctl -k", (0, noise))]))[0]["level"],
        "ok",
        "harmless noise isn't a disk problem"
    );
    let errs = "BTRFS warning (device nvme0n1p2): csum failed root 256 ino 1234 off 0\nblk_update_request: I/O error, dev sda, sector 2048";
    let f = &disk_errors(&says(&[("journalctl -k", (0, errs))]))[0];
    assert!(
        f["level"] == "error"
            && f["detail"]
                .as_str()
                .unwrap()
                .contains("2 read or write errors")
    );
}

#[test]
fn services_failing() {
    let f = services(&says(&[
        ("--user --failed", (0, "")),
        (
            "--failed",
            (0, "cups.service loaded failed failed CUPS Scheduler\n"),
        ),
    ]));
    assert_eq!(f.len(), 1);
    assert_eq!(f[0]["id"], "service:cups.service");
    assert_eq!(f[0]["title"], "CUPS Scheduler stopped working");
    assert!(
        f[0]["fixes"][0]["admin"] == true && f[0]["fixes"][0]["id"] == "service:cups.service",
        "fixed by root"
    );
    assert_eq!(services(&says(&[("--failed", (0, ""))]))[0]["level"], "ok");
}

#[test]
fn crashes_counted() {
    let uid = unsafe { libc::getuid() };
    let mut dumps: Vec<Value> =
        vec![json!({"exe": "/usr/bin/hypridle", "uid": uid, "time": 100}); 3];
    dumps.push(json!({"exe": "/usr/bin/other", "uid": 4321, "time": 100}));
    let d = serde_json::to_string(&dumps).unwrap();
    let f = &crashes(&says(&[("coredumpctl", (0, &d))]))[0];
    assert_eq!(f["title"], "3 crashes this week");
    assert!(
        f["detail"].as_str().unwrap().contains("hypridle (3×)")
            && !f["detail"].as_str().unwrap().contains("other")
    );
    assert!(labels(f) == ["Mark as seen"] && f["fixes"][0]["id"] == "crashes");
    let f = &crashes(&says(&[
        ("coredumpctl", (0, &d)),
        ("checkupdates", (0, "linux 6.1 -> 6.2\n")),
        ("pacman -Qqo", (0, "hypridle\n")),
    ]))[0];
    assert_eq!(
        labels(f),
        ["Mark as seen"],
        "an update for something else: no update offered"
    );
    let f = &crashes(&says(&[
        ("coredumpctl", (0, &d)),
        ("checkupdates", (0, "hypridle 0.1 -> 0.2\n")),
        ("pacman -Qqo", (0, "hypridle\n")),
    ]))[0];
    assert!(
        labels(f) == ["Update", "Mark as seen"]
            && f["fixes"][0]["action"] == "updates"
            && f["detail"].as_str().unwrap().contains("waits for hypridle")
    );
    dumps.push(json!({"exe": "/usr/bin/firefox", "uid": uid, "time": 200}));
    let d2 = serde_json::to_string(&dumps).unwrap();
    let mut s = says(&[("coredumpctl", (0, &d2))]);
    s.seen = 150;
    let f = &crashes(&s)[0];
    assert!(
        f["title"] == "1 crash this week" && f["detail"].as_str().unwrap().contains("firefox"),
        "marked as seen: only the ones since"
    );
    assert_eq!(
        crashes(&says(&[("coredumpctl", (1, "No coredumps found."))]))[0]["level"],
        "ok"
    );
}

#[test]
fn unneeded_packages() {
    let f = &orphans(&says(&[("pacman -Qdtq", (0, "libfoo\nlibbar\n"))]))[0];
    assert!(
        f["title"] == "Unneeded packages: 2"
            && f["detail"].as_str().unwrap().contains("libfoo")
            && f["fixes"][0]["id"] == "orphans"
            && f["fixes"][0]["admin"] == true
    );
    let f = &orphans(&says(&[("pacman -Qdtq", (1, ""))]))[0];
    assert!(f["title"] == "Unneeded packages: none" && f["fixes"].as_array().unwrap().is_empty());
}

#[test]
fn updates_waiting() {
    let mut s = says(&[("checkupdates", (0, "a 1 -> 2\nb 1 -> 2\n"))]);
    s.last_upgrade = Some(s.now - 3.0 * 86400.0);
    let f = &updates(&s)[0];
    assert!(f["title"] == "2 updates waiting" && f["fixes"][0]["action"] == "updates");
    let mut s = says(&[("checkupdates", (2, ""))]);
    s.last_upgrade = Some(s.now - 3.0 * 86400.0);
    assert_eq!(updates(&s)[0]["title"], "Up to date");
}

#[test]
fn arch_news_read() {
    let rss = r#"<rss><channel>
<item><title>Old news</title><link>https://archlinux.org/news/old/</link><pubDate>Mon, 01 Jan 2024 10:00:00 +0000</pubDate></item>
<item><title>Manual step for foo</title><link>https://archlinux.org/news/foo/</link><pubDate>Mon, 12 Oct 2026 10:00:00 +0000</pubDate></item>
</channel></rss>"#;
    let since = rfc2822("Sun, 11 Oct 2026 10:00:00 +0000").unwrap();
    assert_eq!(
        news_since(rss, since),
        [(
            "Manual step for foo".into(),
            "https://archlinux.org/news/foo/".into()
        )]
    );
    assert!(news_since("<html>nope", since).is_empty());
    let mut s = says(&[]);
    s.last_upgrade = Some(since);
    *s.fetched.borrow_mut() = Some(rss.into());
    let f = &arch_news(&s)[0];
    assert!(
        f["level"] == "warn" && f["fixes"][0]["action"] == "open:https://archlinux.org/news/foo/"
    );
    *s.fetched.borrow_mut() = None;
    assert!(arch_news(&s).is_empty(), "no network: says nothing");
}

#[test]
fn the_system_log() {
    let entry = |who: &str, msg: &str| {
        json!({"SYSLOG_IDENTIFIER": who, "MESSAGE": msg, "__REALTIME_TIMESTAMP": "100000000000000000"}).to_string()
    };
    let noise = [
        entry("kernel", "ACPI BIOS Error (bug): Could not resolve symbol"),
        entry("kernel", ""),
        entry(
            "wpa_supplicant",
            "nl80211: kernel reports: multicast RX registrations are not supported",
        ),
    ]
    .join("\n");
    assert_eq!(
        log_errors(&says(&[("journalctl -b -p err", (0, &noise))]))[0]["level"],
        "ok"
    );
    let real = format!(
        "{noise}\n{}\n{}",
        entry("systemd", "Failed to start Foo"),
        entry("systemd", "Failed again")
    );
    let f = &log_errors(&says(&[("journalctl -b -p err", (0, &real))]))[0];
    assert!(
        f["title"] == "2 errors in the system log"
            && f["detail"].as_str().unwrap().contains("systemd (2)")
            && labels(f) == ["Show them", "Mark as seen"]
    );
}

#[test]
fn packages_nothing_offers() {
    let s = says(&[("pacman -Qmq", (0, "yay-bin\nold-thing\nvyntaris\n"))]);
    *s.fetched.borrow_mut() = Some(json!({"results": [{"Name": "yay-bin"}]}).to_string());
    let f = dropped_packages(&s);
    assert!(
        f.len() == 1
            && f[0]["detail"].as_str().unwrap().contains("old-thing")
            && !f[0]["detail"].as_str().unwrap().contains("vyntaris")
    );
    *s.fetched.borrow_mut() = None;
    assert!(dropped_packages(&s).is_empty());
}

#[test]
fn fixes_by_name_only() {
    assert!(!fixes::fix(&says(&[]), &["x; rm -rf /"], false));
    assert!(!fixes::fix(&says(&[]), &["nothing-like-it"], false));
    assert_eq!(
        fixes::user_fix(
            &says(&[("--user --failed", (0, ""))]),
            "user-service:foo.service"
        ),
        Some(true),
        "recovered meanwhile: nothing to do"
    );
}

fn decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' => {
                out.push(u8::from_str_radix(&s[i + 1..i + 3], 16).unwrap());
                i += 2;
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8(out).unwrap()
}

#[test]
fn a_problem_reported() {
    let words: Vec<String> = ["Janko Jankovic", "laptop-janka", "MojaKucaWiFi", "janko"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let home = std::env::var("HOME").unwrap();
    let raw = format!(
        "{home}/.config/x failed for janko on laptop-janka; Janko Jankovic connected to MojaKucaWiFi \
        at 192.168.1.14 (fe80::1c2b:3a4d:5e6f:7081), mac 3c:22:fb:1a:2b:3c, mail janko@example.com, \
        Serial Number: ABC123XYZ; Vyntaris 1.7.0 on vyntaris"
    );
    let out = report::redact(&raw, &words);
    assert!(!out.contains(&home) && out.contains("~/.config/x"));
    assert!(
        !words
            .iter()
            .any(|w| out.to_lowercase().contains(&w.to_lowercase())),
        "{out}"
    );
    assert!(
        [
            "192.168.1.14",
            "fe80::1c2b",
            "3c:22:fb",
            "janko@example.com",
            "ABC123XYZ"
        ]
        .iter()
        .all(|x| !out.contains(x))
    );
    assert!(out.contains("Vyntaris 1.7.0"), "what the system is stays");

    let long = || -> Vec<report::Section> {
        let mut s = vec![("System".to_string(), vec!["Vyntaris 1.7.0".to_string()], 1)];
        s.extend((0..4).map(|i| {
            (
                format!("Log {i}"),
                (0..200)
                    .map(|j| format!("line {j} {}", "x".repeat(80)))
                    .collect(),
                3,
            )
        }));
        s
    };
    let r = report::report(
        "The bar disappeared\nafter plugging in a monitor",
        &[],
        long(),
    );
    let (url, body) = (r["url"].as_str().unwrap(), r["body"].as_str().unwrap());
    assert!(url.len() <= URL_BUDGET);
    assert!(
        body.contains("line 199") && !body.contains("line 0 "),
        "the newest lines stay"
    );
    assert!(
        (0..4).all(|i| body.contains(&format!("### Log {i}"))),
        "each log keeps a few lines"
    );
    assert_eq!(r["title"], "Problem: The bar disappeared");
    assert!(url.starts_with(&format!("{ISSUES}/new?")));
    let q: Vec<(String, String)> = url
        .split_once('?')
        .unwrap()
        .1
        .split('&')
        .map(|kv| {
            let (k, v) = kv.split_once('=').unwrap();
            (k.into(), decode(v))
        })
        .collect();
    assert!(
        q.contains(&("title".into(), r["title"].as_str().unwrap().into()))
            && q.contains(&("body".into(), body.into()))
    );
    let r = report::report(&"x".repeat(20000), &[], long());
    assert!(
        r["url"].as_str().unwrap().len() <= URL_BUDGET
            && r["body"].as_str().unwrap().contains("xxxx")
    );
    let r = report::report(
        &"Šta se dešava, ćirilica ђурђевак ".repeat(400),
        &[],
        long(),
    );
    assert!(
        r["url"].as_str().unwrap().len() <= URL_BUDGET
            && r["body"].as_str().unwrap().contains("Šta se dešava")
    );
}

#[test]
fn every_finding_has_its_fields() {
    let s = says(&[]);
    for f in CHECKS.iter().flat_map(|c| c(&s)) {
        let keys: Vec<&String> = f.as_object().unwrap().keys().collect();
        assert_eq!(keys.len(), 5, "{f}");
        assert!(LEVELS.contains(&f["level"].as_str().unwrap()));
        assert!(
            f["fixes"]
                .as_array()
                .unwrap()
                .iter()
                .all(|o| o["id"].is_string() && o["label"].is_string())
        );
    }
}

#[test]
fn trim_and_scrub_are_asked_for_only_where_they_belong() {
    let ssd_off = says(&[
        ("lsblk", (0, "0 disk\n1 disk\n")),
        ("is-enabled --quiet fstrim.timer", (1, "")),
    ]);
    assert_eq!(trim(&ssd_off)[0]["id"], "trim");
    let ssd_on = says(&[
        ("lsblk", (0, "0 disk\n")),
        ("is-enabled --quiet fstrim.timer", (0, "")),
    ]);
    assert!(trim(&ssd_on).is_empty());
    let spinning = says(&[
        ("lsblk", (0, "1 disk\n0 rom\n")),
        ("is-enabled --quiet fstrim.timer", (1, "")),
    ]);
    assert!(
        trim(&spinning).is_empty(),
        "a hard disk or a DVD isn't trimmed"
    );
    let btrfs = says(&[
        ("findmnt", (0, "btrfs\n")),
        ("is-enabled --quiet btrfs-scrub", (1, "")),
    ]);
    assert_eq!(scrub(&btrfs)[0]["id"], "scrub");
    let ext4 = says(&[
        ("findmnt", (0, "ext4\n")),
        ("is-enabled --quiet btrfs-scrub", (1, "")),
    ]);
    assert!(scrub(&ext4).is_empty());
}

#[test]
fn programs_locks_are_not_broken_links() {
    let home = std::env::temp_dir().join(format!("doctor-links-{}", std::process::id()));
    let profile = home.join(".config/mozilla/firefox/x.default-release");
    let code = home.join(".config/Code - OSS");
    std::fs::create_dir_all(&profile).unwrap();
    std::fs::create_dir_all(&code).unwrap();
    let link = |to: &str, at: &std::path::Path| std::os::unix::fs::symlink(to, at).unwrap();
    link("127.0.1.1:+4242", &profile.join("lock"));
    link("vyntaris-4242", &code.join("SingletonLock"));
    link("1234567890", &code.join("SingletonCookie"));
    link("/nowhere/settings.json", &home.join(".config/old.json"));
    link(profile.to_str().unwrap(), &home.join(".config/here"));
    let found = broken_links_in(&home);
    let _ = std::fs::remove_dir_all(&home);
    assert_eq!(
        found,
        vec![home.join(".config/old.json")],
        "only a link to a file that's gone"
    );
}
