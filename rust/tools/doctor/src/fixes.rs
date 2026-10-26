use crate::checks::{CACHE_KEEP, broken_links, failed_units, home, pacman_running};
use crate::sys::{Sys, state_dir};
use std::fs;
use std::process::Command;

fn sh(cmd: &[&str]) -> bool {
    Command::new(cmd[0])
        .args(&cmd[1..])
        .status()
        .is_ok_and(|s| s.success())
}

pub fn admin_fix(sys: &dyn Sys, id: &str) -> Option<bool> {
    Some(match id {
        "journal" => sh(&["journalctl", "--vacuum-size=200M"]),
        "orphans" => {
            for _ in 0..10 {
                let (code, out) = sys.run(&["pacman", "-Qdtq"]);
                let pkgs: Vec<&str> = out.split_whitespace().collect();
                if code != 0 || pkgs.is_empty() {
                    return Some(true);
                }
                let mut cmd = vec!["pacman", "-Rns", "--noconfirm"];
                cmd.extend(pkgs);
                if !sh(&cmd) {
                    return Some(false);
                }
            }
            true
        }
        "time-sync" => sh(&["timedatectl", "set-ntp", "true"]),
        "pkg-cache" => sh(&["paccache", "-rk1"]) & sh(&["paccache", "-ruk0"]),
        "trim" => sh(&["systemctl", "enable", "--now", "fstrim.timer"]),
        "scrub" => sh(&["systemctl", "enable", "--now", "btrfs-scrub@-.timer"]),
        "mirrors" => sh(&["systemctl", "start", "reflector.service"]),
        "network" => sh(&["systemctl", "enable", "--now", "NetworkManager.service"]),
        "pacman-lock" => {
            if pacman_running(sys) {
                return Some(false);
            }
            let _ = fs::remove_file("/var/lib/pacman/db.lck");
            true
        }
        _ => {
            let unit = id.strip_prefix("service:")?;
            if !failed_units(sys, false).iter().any(|(u, _)| u == unit) {
                return Some(true);
            }
            sh(&["systemctl", "reset-failed", unit]);
            sh(&["systemctl", "restart", unit])
        }
    })
}

fn mark_seen(sys: &dyn Sys, name: &str) -> bool {
    let dir = state_dir();
    let _ = fs::create_dir_all(&dir);
    fs::write(
        dir.join(name),
        ((sys.now() * 1_000_000.0) as u64).to_string(),
    )
    .is_ok()
}

pub fn user_fix(sys: &dyn Sys, id: &str) -> Option<bool> {
    Some(match id {
        "crashes" => mark_seen(sys, "crashes-seen"),
        "log-errors" => mark_seen(sys, "errors-seen"),
        "dead-links" => {
            for l in broken_links() {
                let _ = fs::remove_file(l);
            }
            true
        }
        "app-caches" => {
            let base = home().join(".cache");
            for e in fs::read_dir(&base).into_iter().flatten().flatten() {
                if CACHE_KEEP.contains(&e.file_name().to_string_lossy().as_ref()) {
                    continue;
                }
                let p = e.path();
                match fs::symlink_metadata(&p) {
                    Ok(m) if m.is_dir() => {
                        let _ = fs::remove_dir_all(&p);
                    }
                    _ => {
                        let _ = fs::remove_file(&p);
                    }
                }
            }
            true
        }
        "thumbnails" => {
            let _ = fs::remove_dir_all(home().join(".cache/thumbnails"));
            true
        }
        _ => {
            let unit = id.strip_prefix("user-service:")?;
            if !failed_units(sys, true).iter().any(|(u, _)| u == unit) {
                return Some(true);
            }
            sh(&["systemctl", "--user", "reset-failed", unit]);
            sh(&["systemctl", "--user", "restart", unit])
        }
    })
}

pub fn is_name(id: &str) -> bool {
    !id.is_empty()
        && id
            .chars()
            .all(|c| c.is_alphanumeric() || "_.@:\\-".contains(c))
}

pub fn fix(sys: &dyn Sys, ids: &[&str], root: bool) -> bool {
    let mut ok = true;
    for id in ids {
        if !is_name(id) {
            eprintln!("not a finding: {id}");
            ok = false;
            continue;
        }
        match if root {
            admin_fix(sys, id)
        } else {
            user_fix(sys, id)
        } {
            None => {
                eprintln!(
                    "{id}: nothing {} can fix here",
                    if root { "root" } else { "you" }
                );
                ok = false;
            }
            Some(false) => {
                eprintln!("{id}: couldn't fix it");
                ok = false;
            }
            Some(true) => {}
        }
    }
    ok
}
