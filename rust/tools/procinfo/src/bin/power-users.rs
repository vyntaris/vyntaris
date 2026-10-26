use std::collections::HashMap;
use std::fs;
use vyntaris_procinfo::{exe_name, own_processes, stat_fields};

pub fn is_runner(exe: &str) -> bool {
    let base = exe.trim_end_matches(|c: char| c.is_ascii_digit() || c == '.');
    matches!(base, "python" | "node" | "electron" | "chrome_crashpad_handler" | "java" | "perl" | "ruby" | "bash" | "sh" | "zsh" | "bwrap")
}

pub fn unit_owner(cgroup: &str) -> Option<String> {
    let last = cgroup.trim().rsplit('/').next()?;
    if let Some(scope) = last.strip_prefix("app-").and_then(|s| s.strip_suffix(".scope")) {
        let scope = ["hyprland-", "Hyprland-", "flatpak-"].iter().find_map(|p| scope.strip_prefix(p)).unwrap_or(scope);
        let (name, pid) = scope.rsplit_once('-')?;
        return pid.chars().all(|c| c.is_ascii_digit()).then(|| name.to_string());
    }
    last.strip_suffix(".service").filter(|u| !u.starts_with("user@")).map(str::to_string)
}

fn owner(mut pid: u32, mut exe: String) -> String {
    for _ in 0..8 {
        if !is_runner(&exe) {
            return exe;
        }
        if let Some(o) = fs::read_to_string(format!("/proc/{pid}/cgroup")).ok().as_deref().and_then(unit_owner) {
            return o;
        }
        let Some(parent) = stat_fields(pid).and_then(|f| f.get(1)?.parse::<u32>().ok()) else { return exe };
        if parent <= 1 {
            return exe;
        }
        pid = parent;
        match exe_name(pid) {
            Some(e) => exe = e,
            None => return exe,
        }
    }
    exe
}

fn sample() -> HashMap<String, u64> {
    let mut used = HashMap::new();
    for pid in own_processes() {
        let (Some(exe), Some(f)) = (exe_name(pid), stat_fields(pid)) else { continue };
        let ticks = f.get(11).and_then(|u| u.parse::<u64>().ok()).unwrap_or(0) + f.get(12).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        *used.entry(owner(pid, exe)).or_insert(0) += ticks;
    }
    used
}

fn awake_gpus() -> Vec<&'static str> {
    let mut out = Vec::new();
    for d in fs::read_dir("/sys/bus/pci/devices").into_iter().flatten().flatten() {
        let read = |f: &str| fs::read_to_string(d.path().join(f)).unwrap_or_default();
        if read("vendor").trim() == "0x10de" && read("class").starts_with("0x03") && read("power/runtime_status").trim() == "active" {
            out.push("NVIDIA graphics card");
        }
    }
    out
}

fn main() {
    let seconds: f64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(2.0);
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
    let cpus = std::thread::available_parallelism().map_or(1, |n| n.get()) as f64;
    let before = sample();
    std::thread::sleep(std::time::Duration::from_secs_f64(seconds));
    let after = sample();
    let mut share: Vec<(String, f64)> = after
        .iter()
        .map(|(exe, t)| (exe.clone(), (*t as f64 - *before.get(exe).unwrap_or(t) as f64) / ticks / seconds / cpus * 100.0))
        .collect();
    share.sort_by(|a, b| b.1.total_cmp(&a.1));
    for (exe, pct) in share.into_iter().take(5) {
        if pct >= 0.5 {
            println!("{pct:.0} {exe}");
        }
    }
    for gpu in awake_gpus() {
        println!("gpu {gpu}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runners_and_whose_they_are() {
        assert!(is_runner("python3.14") && is_runner("electron42") && is_runner("node") && !is_runner("firefox"));
        assert_eq!(unit_owner("0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-Hyprland-code-1234.scope").as_deref(), Some("code"));
        assert_eq!(unit_owner("0::/user.slice/user-1000.slice/user@1000.service/session.slice/vyntaris-shell.service").as_deref(), Some("vyntaris-shell"));
        assert_eq!(unit_owner("0::/user.slice/user-1000.slice/user@1000.service"), None);
    }
}
