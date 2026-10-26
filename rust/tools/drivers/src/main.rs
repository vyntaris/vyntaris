use regex::Regex;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::sync::LazyLock;

const STATE: &str = "/var/lib/vyntaris/drivers.json";
const LIB: &str = "/usr/lib/vyntaris";

const NVIDIA: u32 = 0x10de;
const AMD_GPU: u32 = 0x1002;
const INTEL: u32 = 0x8086;
const AMD_CPU: u32 = 0x1022;
const BROADCOM: u32 = 0x14e4;

fn read(path: impl AsRef<Path>) -> String {
    fs::read_to_string(path).map(|s| s.trim().to_string()).unwrap_or_default()
}

fn hex_id(path: impl AsRef<Path>) -> i64 {
    i64::from_str_radix(read(path).trim_start_matches("0x"), 16).unwrap_or(-1)
}

#[derive(Default)]
pub struct Names {
    vendors: HashMap<u32, String>,
    devices: HashMap<(u32, u32), String>,
}

impl Names {
    pub fn load(path: &str) -> Names {
        let mut n = Names::default();
        let Ok(text) = fs::read(path) else { return n };
        let text = String::from_utf8_lossy(&text);
        let mut vendor = None;
        for line in text.lines() {
            if line.starts_with('#') || line.trim().is_empty() {
                continue;
            }
            if line.starts_with("C ") {
                break;
            }
            let id = |s: &str| (s.len() >= 4 && s.as_bytes()[..4].iter().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()))
                .then(|| u32::from_str_radix(&s[..4], 16).ok()).flatten();
            if let Some(v) = id(line).filter(|_| line.as_bytes().get(4).is_some_and(u8::is_ascii_whitespace)) {
                vendor = Some(v);
                n.vendors.insert(v, line[4..].trim().to_string());
            } else if let Some(rest) = line.strip_prefix('\t').filter(|r| !r.starts_with('\t'))
                && let (Some(d), Some(v)) = (id(rest).filter(|_| rest.as_bytes().get(4).is_some_and(u8::is_ascii_whitespace)), vendor) {
                    n.devices.insert((v, d), rest[4..].trim().to_string());
                }
        }
        n
    }

    pub fn name(&self, vendor: u32, device: u32) -> String {
        static BRACKET: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\[([^\]]+)\]").unwrap());
        static COMPANY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r",?\s+(Corporation|Corp\.|Inc\.|Co\., Ltd\.|Semiconductor|Technology|Limited|Ltd\.?)(\s.*|$)").unwrap());
        let mut v = self.vendors.get(&vendor).cloned().unwrap_or_else(|| format!("{vendor:04x}"));
        if let Some(m) = BRACKET.captures(&v) {
            v = m[1].split('/').next().unwrap_or("").to_string();
        }
        let v = COMPANY.replace(&v, "").trim().to_string();
        let d = self.devices.get(&(vendor, device)).cloned().unwrap_or_else(|| format!("{device:04x}"));
        let d = BRACKET.captures(&d).map_or(d.clone(), |m| m[1].to_string());
        let d = d.split(" / ").next().unwrap_or("").to_string();
        if d.to_lowercase().starts_with(&v.to_lowercase()) { d } else { format!("{v} {d}") }
    }
}

#[derive(Clone)]
pub struct Pci {
    pub vendor: u32,
    pub device: u32,
    pub class: u32,
    pub driver: String,
}

#[derive(Clone)]
pub struct Usb {
    pub vendor: u32,
    pub device: u32,
    pub classes: HashSet<u32>,
    pub name: String,
}

pub trait Machine {
    fn pci(&self) -> Vec<Pci>;
    fn usb(&self) -> Vec<Usb>;
    fn virtualization(&self) -> String;
    fn cpuinfo(&self) -> String;
}

struct Real;

impl Machine for Real {
    fn pci(&self) -> Vec<Pci> {
        let mut dirs: Vec<_> = fs::read_dir("/sys/bus/pci/devices").into_iter().flatten().flatten().map(|e| e.path()).collect();
        dirs.sort();
        dirs.iter()
            .map(|d| Pci {
                vendor: hex_id(d.join("vendor")).max(0) as u32,
                device: hex_id(d.join("device")).max(0) as u32,
                class: hex_id(d.join("class")).max(0) as u32,
                driver: fs::read_link(d.join("driver")).ok().and_then(|p| p.file_name().map(|f| f.to_string_lossy().to_string())).unwrap_or_default(),
            })
            .collect()
    }
    fn usb(&self) -> Vec<Usb> {
        let mut dirs: Vec<_> = fs::read_dir("/sys/bus/usb/devices").into_iter().flatten().flatten().map(|e| e.path()).collect();
        dirs.sort();
        dirs.iter()
            .filter(|d| d.join("idVendor").exists())
            .map(|d| {
                let classes = fs::read_dir(d).into_iter().flatten().flatten()
                    .filter(|e| e.file_name().to_string_lossy().contains(':'))
                    .filter_map(|e| u32::try_from(hex_id(e.path().join("bInterfaceClass"))).ok())
                    .collect();
                let name = [read(d.join("manufacturer")), read(d.join("product"))].into_iter().filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" ");
                Usb { vendor: hex_id(d.join("idVendor")).max(0) as u32, device: hex_id(d.join("idProduct")).max(0) as u32, classes, name }
            })
            .collect()
    }
    fn virtualization(&self) -> String {
        Command::new("systemd-detect-virt").arg("--vm").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default()
    }
    fn cpuinfo(&self) -> String {
        read("/proc/cpuinfo")
    }
}

#[derive(Clone, Serialize)]
pub struct Device {
    pub id: String,
    pub kind: String,
    pub name: String,
    pub packages: Vec<String>,
    pub note: String,
    pub restart: bool,
    pub setup: Option<String>,
    #[serde(default)]
    pub missing: Vec<String>,
    #[serde(default)]
    pub unavailable: Vec<String>,
}

fn device(id: &str, kind: &str, name: String, packages: &[&str], note: &str, restart: bool, setup: Option<&str>) -> Device {
    Device {
        id: id.into(), kind: kind.into(), name, packages: packages.iter().map(|p| p.to_string()).collect(), note: note.into(), restart,
        setup: setup.map(str::to_string), missing: vec![], unavailable: vec![],
    }
}

pub fn needs(m: &dyn Machine, multilib: bool, pci_names: &Names, usb_names: &Names) -> Vec<Device> {
    let pci = m.pci();
    let mut found = Vec::new();

    let gpus: Vec<&Pci> = pci.iter().filter(|p| p.class >> 16 == 0x03).collect();
    let hybrid = gpus.iter().map(|g| g.vendor).collect::<HashSet<_>>().len() > 1;
    for g in &gpus {
        let name = pci_names.name(g.vendor, g.device);
        match g.vendor {
            NVIDIA if g.device >= 0x1e00 => {
                let mut pkgs = vec!["nvidia-open", "nvidia-utils", "egl-wayland", "linux-firmware-nvidia"];
                if hybrid {
                    pkgs.push("nvidia-prime");
                }
                if multilib {
                    pkgs.push("lib32-nvidia-utils");
                }
                let note = format!("The faster driver from NVIDIA.{}", if hybrid { " Apps use it when started with prime-run." } else { "" });
                found.push(device("gpu-nvidia", "Graphics", name, &pkgs, &note, true, Some("nvidia")));
            }
            NVIDIA => found.push(device("gpu-nvidia", "Graphics", name, &["mesa", "linux-firmware-nvidia"],
                "Older than NVIDIA's open driver supports: the open nouveau driver runs it.", false, None)),
            AMD_GPU => {
                let mut pkgs = vec!["mesa", "vulkan-radeon", "linux-firmware-amdgpu", "linux-firmware-radeon"];
                if multilib {
                    pkgs.extend(["lib32-mesa", "lib32-vulkan-radeon"]);
                }
                found.push(device("gpu-amd", "Graphics", name, &pkgs, "", false, None));
            }
            INTEL => {
                let mut pkgs = vec!["mesa", "vulkan-intel", "intel-media-driver"];
                if multilib {
                    pkgs.extend(["lib32-mesa", "lib32-vulkan-intel"]);
                }
                found.push(device("gpu-intel", "Graphics", name, &pkgs, "", false, None));
            }
            _ => {}
        }
    }

    for n in pci.iter().filter(|p| p.class >> 8 == 0x0280) {
        let name = pci_names.name(n.vendor, n.device);
        if n.vendor == BROADCOM && n.driver.is_empty() {
            found.push(device("wifi-broadcom", "Wi-Fi", name, &["broadcom-wl-dkms", "linux-headers"],
                "Broadcom's own driver: no open one takes this chip.", true, None));
        } else {
            let firmware = match n.vendor {
                INTEL => "linux-firmware-intel",
                0x168c | 0x17cb => "linux-firmware-atheros",
                0x14c3 => "linux-firmware-mediatek",
                0x10ec => "linux-firmware-realtek",
                BROADCOM => "linux-firmware-broadcom",
                _ => "linux-firmware-other",
            };
            found.push(device("wifi", "Wi-Fi", name, &[firmware], "", false, None));
        }
    }

    if let Some(a) = pci.iter().find(|a| {
        (a.vendor == INTEL && matches!(a.class >> 8, 0x0401 | 0x0403) && (a.driver.starts_with("sof") || a.driver.starts_with("snd_sof")))
            || (a.vendor == AMD_CPU && a.class >> 8 == 0x0480)
    }) {
        found.push(device("sound-dsp", "Sound", pci_names.name(a.vendor, a.device), &["sof-firmware", "alsa-ucm-conf"],
            "Firmware for the built-in microphones and speakers.", true, None));
    }

    let cpu = m.cpuinfo();
    if cpu.contains("GenuineIntel") {
        found.push(device("microcode", "Processor", "Intel processor".into(), &["intel-ucode"], "Fixes from Intel, loaded at every start.", true, None));
    } else if cpu.contains("AuthenticAMD") {
        found.push(device("microcode", "Processor", "AMD processor".into(), &["amd-ucode"], "Fixes from AMD, loaded at every start.", true, None));
    }

    let usb = m.usb();
    for p in usb.iter().filter(|u| u.classes.contains(&0x07)) {
        let name = if p.name.is_empty() { usb_names.name(p.vendor, p.device) } else { p.name.clone() };
        let mut pkgs = vec!["cups", "cups-filters", "ipp-usb", "gutenprint", "foomatic-db-engine", "foomatic-db"];
        let mut note = "Most printers made since 2015 work without a driver of their own.".to_string();
        if p.vendor == 0x03f0 {
            pkgs.push("hplip");
            note = "HP's own driver, for its printers and scanners.".into();
        } else if p.vendor == 0x04f9 {
            note.push_str(" Brother's own driver (brlaser) is in the AUR, if this one needs it.");
        }
        found.push(device(&format!("printer-{:04x}-{:04x}", p.vendor, p.device), "Printer", name, &pkgs, &note, false, None));
    }
    if let Some(s) = usb.iter().find(|u| (u.classes.contains(&0x07) || u.classes.contains(&0xff))
        && [0x03f0, 0x04b8, 0x04a9, 0x04f9, 0x0924, 0x055f].contains(&u.vendor))
    {
        let name = if s.name.is_empty() { usb_names.name(s.vendor, s.device) } else { s.name.clone() };
        let mut pkgs = vec!["sane", "sane-airscan", "ipp-usb"];
        if s.vendor == 0x03f0 {
            pkgs.push("hplip");
        }
        found.push(device("scanner", "Scanner", name, &pkgs, "Scanning with Simple Scan or any app that scans.", false, None));
    }

    let virt = m.virtualization();
    let guest: Option<&[&str]> = match virt.as_str() {
        "oracle" => Some(&["virtualbox-guest-utils"]),
        "kvm" | "qemu" => Some(&["qemu-guest-agent", "spice-vdagent"]),
        "vmware" => Some(&["open-vm-tools"]),
        _ => None,
    };
    if let Some(g) = guest {
        found.push(device("vm-guest", "Virtual machine", format!("Running in {virt}"), g,
            "Shared clipboard and a screen that follows the window's size.", false, None));
    }
    found
}

fn pacman(args: &[&str]) -> (bool, String) {
    Command::new("pacman").args(args).output().map(|o| (o.status.success(), String::from_utf8_lossy(&o.stdout).into_owned())).unwrap_or((false, String::new()))
}

fn installed(pkgs: &[String]) -> HashSet<String> {
    if pkgs.is_empty() {
        return HashSet::new();
    }
    let mut args = vec!["-T"];
    args.extend(pkgs.iter().map(String::as_str));
    let missing: HashSet<String> = pacman(&args).1.split_whitespace().map(str::to_string).collect();
    pkgs.iter().filter(|p| !missing.contains(*p)).cloned().collect()
}

fn available(pkgs: &[String]) -> HashSet<String> {
    if pkgs.is_empty() {
        return HashSet::new();
    }
    let mut args = vec!["-Sp", "--print-format", "%n"];
    args.extend(pkgs.iter().map(String::as_str));
    if pacman(&args).0 {
        return pkgs.iter().cloned().collect();
    }
    pkgs.iter().filter(|p| pacman(&["-Sp", "--print-format", "%n", p]).0).cloned().collect()
}

fn multilib() -> bool {
    Command::new("pacman-conf").arg("--repo-list").output().map(|o| String::from_utf8_lossy(&o.stdout).split_whitespace().any(|r| r == "multilib")).unwrap_or(false)
}

fn survey() -> Vec<Device> {
    let mut devices = needs(&Real, multilib(), &Names::load("/usr/share/hwdata/pci.ids"), &Names::load("/usr/share/hwdata/usb.ids"));
    let want: Vec<String> = devices.iter().flat_map(|d| d.packages.clone()).collect::<BTreeSet<_>>().into_iter().collect();
    let have = installed(&want);
    let rest: Vec<String> = want.iter().filter(|p| !have.contains(*p)).cloned().collect();
    let can = available(&rest);
    for d in &mut devices {
        d.missing = d.packages.iter().filter(|p| !have.contains(*p) && can.contains(*p)).cloned().collect();
        d.unavailable = d.packages.iter().filter(|p| !have.contains(*p) && !can.contains(*p)).cloned().collect();
    }
    devices
}

fn setup_nvidia(hybrid: bool) {
    let _ = fs::create_dir_all("/etc/modprobe.d");
    let _ = fs::write("/etc/modprobe.d/nvidia-desktop.conf", "options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_DynamicPowerManagement=0x02\n");
    if hybrid && Path::new(&format!("{LIB}/prime-run")).exists() {
        let _ = fs::copy(format!("{LIB}/prime-run"), "/usr/local/bin/prime-run");
        let _ = fs::set_permissions("/usr/local/bin/prime-run", std::os::unix::fs::PermissionsExt::from_mode(0o755));
    }
    let _ = Command::new("systemctl").args(["enable", "nvidia-suspend.service", "nvidia-hibernate.service", "nvidia-resume.service"]).output();
}

fn wait_for_pacman(seconds: u32) -> bool {
    for _ in 0..seconds {
        if !Path::new("/var/lib/pacman/db.lck").exists() {
            return true;
        }
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
    false
}

fn online() -> bool {
    match Command::new("nmcli").args(["-t", "-f", "CONNECTIVITY", "general"]).output() {
        Ok(o) if o.status.success() => matches!(String::from_utf8_lossy(&o.stdout).trim(), "full" | "limited" | "unknown"),
        _ => true,
    }
}

fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn record(entries: Vec<Value>) {
    let mut state: Value = fs::read_to_string(STATE).ok().and_then(|s| serde_json::from_str(&s).ok()).filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut all: Vec<Value> = state.get("installed").and_then(Value::as_array).cloned().unwrap_or_default();
    all.extend(entries);
    let keep = all.len().saturating_sub(30);
    state["installed"] = Value::Array(all.split_off(keep));
    state["checked"] = json!(now());
    let _ = fs::create_dir_all("/var/lib/vyntaris");
    let tmp = format!("{STATE}.new");
    if fs::write(&tmp, state.to_string()).is_ok() {
        let _ = fs::set_permissions(&tmp, std::os::unix::fs::PermissionsExt::from_mode(0o644));
        let _ = fs::rename(&tmp, STATE);
    }
}

fn install(auto: bool) -> i32 {
    if unsafe { libc::geteuid() } != 0 {
        eprintln!("installing drivers needs root");
        return 1;
    }
    if auto && !online() {
        return 0;
    }
    if !wait_for_pacman(if auto { 600 } else { 60 }) {
        eprintln!("another install is running: try again once it's done");
        return 1;
    }
    let devices = survey();
    let todo: Vec<&Device> = devices.iter().filter(|d| !d.missing.is_empty()).collect();
    if todo.is_empty() {
        record(vec![]);
        if !auto {
            println!("every driver is installed");
        }
        return 0;
    }
    let pkgs: Vec<String> = todo.iter().flat_map(|d| d.missing.clone()).collect::<BTreeSet<_>>().into_iter().collect();
    println!("installing: {}", pkgs.join(" "));
    let mut done = false;
    for _ in 0..3 {
        if Command::new("pacman").args(["-S", "--needed", "--noconfirm"]).args(&pkgs).status().is_ok_and(|s| s.success()) {
            done = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_secs(5));
    }
    if !done {
        eprintln!("the drivers couldn't be installed (no network, or the system needs updating first)");
        return 1;
    }
    let hybrid = devices.iter().filter(|d| d.kind == "Graphics").map(|d| d.id.clone()).collect::<HashSet<_>>().len() > 1;
    if todo.iter().any(|d| d.setup.as_deref() == Some("nvidia")) {
        setup_nvidia(hybrid);
    }
    let at = now();
    record(todo.iter().map(|d| json!({"at": at, "id": d.id, "kind": d.kind, "name": d.name, "packages": d.missing, "restart": d.restart})).collect());
    for d in &todo {
        println!("{}: {}: {}", d.kind, d.name, d.missing.join(" "));
    }
    0
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let code = match a.as_slice() {
        [] => {
            println!("{}", json!({ "devices": survey() }));
            0
        }
        ["--install"] => install(false),
        ["--install", "--auto"] | ["--auto", "--install"] => install(true),
        _ => {
            eprintln!("drivers [--install [--auto]]");
            2
        }
    };
    std::process::exit(code);
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fake {
        pci: Vec<Pci>,
        usb: Vec<Usb>,
        cpu: &'static str,
        virt: &'static str,
    }
    impl Machine for Fake {
        fn pci(&self) -> Vec<Pci> { self.pci.clone() }
        fn usb(&self) -> Vec<Usb> { self.usb.clone() }
        fn virtualization(&self) -> String { self.virt.into() }
        fn cpuinfo(&self) -> String { self.cpu.into() }
    }
    fn pci(vendor: u32, device: u32, class: u32, driver: &str) -> Pci { Pci { vendor, device, class, driver: driver.into() } }
    fn usb(vendor: u32, device: u32, classes: &[u32], name: &str) -> Usb { Usb { vendor, device, classes: classes.iter().copied().collect(), name: name.into() } }
    fn machine(pci: Vec<Pci>, usb: Vec<Usb>, cpu: &'static str, virt: &'static str, multilib: bool) -> HashMap<String, Device> {
        let n = Names::default();
        needs(&Fake { pci, usb, cpu, virt }, multilib, &n, &n).into_iter().map(|d| (d.id.clone(), d)).collect()
    }
    fn hw(pci: Vec<Pci>) -> HashMap<String, Device> { machine(pci, vec![], "GenuineIntel", "", false) }

    #[test]
    fn wifi_takes_its_makers_firmware_only() {
        for (vendor, firmware) in [(0x8086, "linux-firmware-intel"), (0x168c, "linux-firmware-atheros"), (0x14c3, "linux-firmware-mediatek"),
                                   (0x10ec, "linux-firmware-realtek"), (0x1814, "linux-firmware-other")] {
            let f = hw(vec![pci(vendor, 0x1234, 0x028000, "x")]);
            assert_eq!(f["wifi"].packages, [firmware], "{vendor:x}");
        }
    }

    #[test]
    fn graphics() {
        let f = hw(vec![pci(0x10de, 0x2560, 0x030000, "nvidia"), pci(0x1002, 0x1638, 0x030000, "amdgpu")]);
        assert_eq!(f["gpu-nvidia"].packages[..2], ["nvidia-open", "nvidia-utils"]);
        assert!(f["gpu-nvidia"].packages.contains(&"nvidia-prime".into()) && f["gpu-nvidia"].setup.as_deref() == Some("nvidia"));
        assert!(f["gpu-nvidia"].restart);
        assert_eq!(f["gpu-amd"].packages, ["mesa", "vulkan-radeon", "linux-firmware-amdgpu", "linux-firmware-radeon"]);
        assert!(f["gpu-nvidia"].packages.contains(&"linux-firmware-nvidia".into()));
        let f = hw(vec![pci(0x10de, 0x1c03, 0x030000, "")]);
        assert!(f["gpu-nvidia"].packages == ["mesa", "linux-firmware-nvidia"] && f["gpu-nvidia"].note.contains("nouveau"));
        assert!(!hw(vec![pci(0x10de, 0x2560, 0x030000, "")])["gpu-nvidia"].packages.contains(&"nvidia-prime".into()));
        let f = machine(vec![pci(0x8086, 0x46a6, 0x030000, "")], vec![], "GenuineIntel", "", true);
        assert!(f["gpu-intel"].packages.contains(&"lib32-vulkan-intel".into()));
    }

    #[test]
    fn wifi_and_sound() {
        assert_eq!(hw(vec![pci(0x14e4, 0x4331, 0x028000, "")])["wifi-broadcom"].packages[0], "broadcom-wl-dkms");
        let f = hw(vec![pci(0x14e4, 0x43a0, 0x028000, "brcmfmac")]);
        assert!(f.contains_key("wifi") && !f.contains_key("wifi-broadcom"));
        assert!(hw(vec![pci(0x8086, 0x51c8, 0x040100, "sof-audio-pci-intel-tgl")]).contains_key("sound-dsp"));
        assert!(!hw(vec![pci(0x8086, 0x02c8, 0x040300, "snd_hda_intel")]).contains_key("sound-dsp"));
    }

    #[test]
    fn processor_and_virtual_machines() {
        assert_eq!(machine(vec![], vec![], "GenuineIntel", "", false)["microcode"].packages, ["intel-ucode"]);
        assert_eq!(machine(vec![], vec![], "AuthenticAMD", "", false)["microcode"].packages, ["amd-ucode"]);
        assert_eq!(machine(vec![], vec![], "", "kvm", false)["vm-guest"].packages, ["qemu-guest-agent", "spice-vdagent"]);
    }

    #[test]
    fn printers_and_scanners() {
        let f = machine(vec![], vec![usb(0x03f0, 0x2b17, &[0x07, 0xff], "HP LaserJet")], "", "", false);
        let p = &f["printer-03f0-2b17"];
        assert!(p.packages.contains(&"hplip".into()) && p.name == "HP LaserJet");
        assert!(f.contains_key("scanner") && f["scanner"].packages.contains(&"sane-airscan".into()));
        let f = machine(vec![], vec![usb(0x04f9, 0x0042, &[0x07], "")], "", "", false);
        assert!(f["printer-04f9-0042"].packages.contains(&"ipp-usb".into()) && f["printer-04f9-0042"].note.contains("brlaser"));
        let f = machine(vec![], vec![usb(0x04e8, 0x6860, &[0xff, 0x06], "Samsung Galaxy")], "", "", false);
        assert!(!f.contains_key("scanner") && !f.keys().any(|k| k.starts_with("printer")));
    }

    #[test]
    fn names() {
        let n = Names::load("/usr/share/hwdata/pci.ids");
        if n.vendors.is_empty() {
            return;
        }
        assert_eq!(n.name(0x10de, 0x2560), "NVIDIA GeForce RTX 3060 Mobile");
        assert_eq!(n.name(0x1002, 0x1638), "AMD Radeon Vega Series");
        assert!(n.name(0x14e4, 0x4331).starts_with("Broadcom BCM4331"));
    }
}
