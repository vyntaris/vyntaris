use std::process::Command;

pub trait Sys {
    fn run(&self, cmd: &[&str]) -> (i32, String);
    fn fetch(&self, url: &str) -> Option<String>;
    fn crashes_seen(&self) -> u64;
    fn last_upgrade(&self) -> Option<f64>;
    fn now(&self) -> f64;
    fn private_words(&self) -> Vec<String>;
}

pub struct Real;

pub fn state_dir() -> std::path::PathBuf {
    vyntaris_core::paths::state_home().join("vyntaris")
}

pub fn read_seen(name: &str) -> u64 {
    std::fs::read_to_string(state_dir().join(name))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

pub fn local_seconds(stamp: &str) -> Option<f64> {
    let n = |a: usize, b: usize| stamp.get(a..b)?.parse::<i32>().ok();
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    tm.tm_year = n(0, 4)? - 1900;
    tm.tm_mon = n(5, 7)? - 1;
    tm.tm_mday = n(8, 10)?;
    tm.tm_hour = n(11, 13)?;
    tm.tm_min = n(14, 16)?;
    tm.tm_sec = n(17, 19)?;
    tm.tm_isdst = -1;
    let t = unsafe { libc::mktime(&mut tm) };
    (t != -1).then_some(t as f64)
}

impl Sys for Real {
    fn run(&self, cmd: &[&str]) -> (i32, String) {
        match Command::new(cmd[0]).args(&cmd[1..]).output() {
            Ok(o) => (
                o.status.code().unwrap_or(1),
                String::from_utf8_lossy(&o.stdout).into_owned(),
            ),
            Err(_) => (127, String::new()),
        }
    }
    fn fetch(&self, url: &str) -> Option<String> {
        let (code, out) = self.run(&[
            "curl",
            "-fsSL",
            "--max-time",
            "8",
            "-A",
            "Vyntaris Dr. Help",
            url,
        ]);
        (code == 0).then_some(out)
    }
    fn crashes_seen(&self) -> u64 {
        read_seen("crashes-seen")
    }
    fn last_upgrade(&self) -> Option<f64> {
        let log = std::fs::read("/var/log/pacman.log").ok()?;
        let log = String::from_utf8_lossy(&log);
        let line = log
            .lines()
            .rfind(|l| l.contains("starting full system upgrade"))?;
        local_seconds(line.strip_prefix('[')?.get(..19)?)
    }
    fn now(&self) -> f64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0.0, |d| d.as_secs_f64())
    }
    fn private_words(&self) -> Vec<String> {
        crate::report::private_words(self)
    }
}
