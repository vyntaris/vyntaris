use std::fs;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};

type Codes = &'static [(i32, (&'static str, &'static str))];
const SWITCHES: &[(&str, Codes)] =
    &[("Ideapad extra buttons", &[(0x10C, ("camera", "on")), (0x10D, ("camera", "off"))])];
const LEDS: &[(&str, &str)] = &[("fnlock", "/sys/class/leds/platform::fnlock")];

const EV_KEY: u16 = 1;
const EV_MSC: u16 = 4;
const MSC_SCAN: u16 = 4;
const EVENT: usize = 24;

struct Places {
    run: PathBuf,
    keep: PathBuf,
}

impl Places {
    fn publish(&self, name: &str, state: &str) {
        for dir in [&self.run, &self.keep] {
            let _ = fs::create_dir_all(dir);
            let tmp = dir.join(format!(".{name}"));
            if fs::write(&tmp, format!("{state}\n")).is_ok() {
                let _ = fs::set_permissions(&tmp, std::os::unix::fs::PermissionsExt::from_mode(0o644));
                let _ = fs::rename(&tmp, dir.join(name));
            }
        }
        println!("{name}: {state}");
    }
}

fn devices(list: &str) -> Vec<(PathBuf, Codes)> {
    let mut out = Vec::new();
    for block in list.split("\n\n") {
        let name = block.lines().find_map(|l| l.strip_prefix("N: Name=\"")).map(|n| n.trim_end_matches('"'));
        let event = block.split(|c: char| !c.is_alphanumeric()).find(|w| w.starts_with("event") && w[5..].parse::<u32>().is_ok());
        if let (Some(name), Some(event)) = (name, event)
            && let Some((_, table)) = SWITCHES.iter().find(|(n, _)| *n == name) {
                out.push((Path::new("/dev/input").join(event), *table));
            }
    }
    out
}

fn read_events(data: &[u8], scan: &mut Option<i32>, table: Codes) -> Vec<(&'static str, &'static str)> {
    let mut out = Vec::new();
    for ev in data.as_chunks::<EVENT>().0 {
        let typ = u16::from_ne_bytes([ev[16], ev[17]]);
        let code = u16::from_ne_bytes([ev[18], ev[19]]);
        let value = i32::from_ne_bytes([ev[20], ev[21], ev[22], ev[23]]);
        if typ == EV_MSC && code == MSC_SCAN {
            *scan = Some(value);
        } else if typ == EV_KEY && value == 1
            && let Some(&(_, what)) = table.iter().find(|(s, _)| Some(*s) == *scan) {
                out.push(what);
            }
    }
    out
}

fn led_state(path: &str) -> &'static str {
    match fs::read_to_string(format!("{path}/brightness")) {
        Ok(s) if s.trim() != "0" => "on",
        _ => "off",
    }
}

fn rearm(f: &mut fs::File) {
    use std::io::{Seek, SeekFrom};
    let _ = f.seek(SeekFrom::Start(0));
    let _ = f.read(&mut [0u8; 16]);
}

fn main() {
    let places = Places { run: "/run/laptop-switches".into(), keep: "/var/lib/laptop-switches".into() };
    let _ = fs::create_dir_all(&places.run);
    if let Ok(entries) = fs::read_dir(&places.keep) {
        for e in entries.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if !name.starts_with('.') && !LEDS.iter().any(|(n, _)| *n == name)
                && let Ok(state) = fs::read_to_string(e.path()) {
                    places.publish(&name, state.trim());
                }
        }
    }

    let mut inputs: Vec<(fs::File, Codes, Option<i32>)> = Vec::new();
    for (path, table) in devices(&fs::read_to_string("/proc/bus/input/devices").unwrap_or_default()) {
        if let Ok(f) = fs::File::open(&path) {
            inputs.push((f, table, None));
        }
    }
    let mut leds: Vec<(fs::File, &str, &str)> = Vec::new();
    for (name, path) in LEDS {
        if let Ok(mut f) = fs::File::open(format!("{path}/brightness_hw_changed")) {
            rearm(&mut f);
            places.publish(name, led_state(path));
            leds.push((f, name, path));
        }
    }
    if inputs.is_empty() && leds.is_empty() {
        println!("no known switch devices");
        loop {
            std::thread::sleep(std::time::Duration::from_secs(3600));
        }
    }

    let mut fds: Vec<libc::pollfd> = inputs
        .iter()
        .map(|(f, _, _)| libc::pollfd { fd: f.as_raw_fd(), events: libc::POLLIN, revents: 0 })
        .chain(leds.iter().map(|(f, _, _)| libc::pollfd { fd: f.as_raw_fd(), events: libc::POLLPRI | libc::POLLERR, revents: 0 }))
        .collect();
    let mut buf = vec![0u8; EVENT * 64];
    loop {
        let n = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if n < 0 {
            continue;
        }
        for (i, p) in fds.iter_mut().enumerate() {
            if p.revents == 0 {
                continue;
            }
            p.revents = 0;
            if i < inputs.len() {
                let (f, table, scan) = &mut inputs[i];
                if let Ok(len) = f.read(&mut buf) {
                    for (name, state) in read_events(&buf[..len], scan, table) {
                        places.publish(name, state);
                    }
                }
            } else {
                let (f, name, path) = &mut leds[i - inputs.len()];
                rearm(f);
                places.publish(name, led_state(path));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn event(typ: u16, code: u16, value: i32) -> Vec<u8> {
        let mut e = vec![0u8; 16];
        e.extend(typ.to_ne_bytes());
        e.extend(code.to_ne_bytes());
        e.extend(value.to_ne_bytes());
        e
    }

    #[test]
    fn the_device_is_found_by_name() {
        let list = "I: Bus=0019\nN: Name=\"Power Button\"\nH: Handlers=kbd event3\n\n\
                    I: Bus=0019\nN: Name=\"Ideapad extra buttons\"\nH: Handlers=rfkill kbd event10\n";
        let d = devices(list);
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].0, Path::new("/dev/input/event10"));
    }

    #[test]
    fn a_scancode_then_a_press_says_which() {
        let table = SWITCHES[0].1;
        let mut scan = None;
        let mut data = event(EV_MSC, MSC_SCAN, 0x10C);
        data.extend(event(EV_KEY, 240, 1));
        data.extend(event(EV_KEY, 240, 0));
        data.extend(event(EV_MSC, MSC_SCAN, 0x10D));
        data.extend(event(EV_KEY, 240, 1));
        assert_eq!(read_events(&data, &mut scan, table), [("camera", "on"), ("camera", "off")]);
        let mut data = event(EV_MSC, MSC_SCAN, 0x999);
        data.extend(event(EV_KEY, 240, 1));
        assert!(read_events(&data, &mut scan, table).is_empty());
    }

    #[test]
    fn published_beside_and_kept() {
        let dir = std::env::temp_dir().join(format!("switches-{}", std::process::id()));
        let p = Places { run: dir.join("run"), keep: dir.join("keep") };
        p.publish("camera", "off");
        assert_eq!(fs::read_to_string(dir.join("run/camera")).unwrap(), "off\n");
        assert_eq!(fs::read_to_string(dir.join("keep/camera")).unwrap(), "off\n");
        let _ = fs::remove_dir_all(dir);
    }
}
