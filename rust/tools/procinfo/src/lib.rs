use std::fs;
use std::os::unix::fs::MetadataExt;

pub fn own_processes() -> Vec<u32> {
    let uid = unsafe { libc::getuid() };
    let me = std::process::id();
    fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.parse::<u32>().ok().filter(|p| *p != me).map(|p| (p, e)))
        .filter(|(_, e)| e.metadata().map(|m| m.uid() == uid).unwrap_or(false))
        .map(|(p, _)| p)
        .collect()
}

pub fn stat_fields(pid: u32) -> Option<Vec<String>> {
    let s = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    Some(s.rsplit_once(')')?.1.split_whitespace().map(str::to_string).collect())
}

pub fn exe_name(pid: u32) -> Option<String> {
    let name = fs::read_link(format!("/proc/{pid}/exe")).ok()?.file_name()?.to_string_lossy().to_string();
    Some(name.strip_suffix(" (deleted)").unwrap_or(&name).to_string())
}
