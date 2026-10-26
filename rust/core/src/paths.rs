use std::path::PathBuf;

fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

fn xdg(var: &str, fallback: &str) -> PathBuf {
    std::env::var_os(var).map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| home().join(fallback))
}

pub fn config_home() -> PathBuf {
    xdg("XDG_CONFIG_HOME", ".config")
}
pub fn cache_home() -> PathBuf {
    xdg("XDG_CACHE_HOME", ".cache")
}
pub fn state_home() -> PathBuf {
    xdg("XDG_STATE_HOME", ".local/state")
}
pub fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir)
}

pub fn shell_dir() -> PathBuf {
    if let Some(d) = std::env::var_os("VYNTARIS_SHELL_DIR").map(PathBuf::from).filter(|p| p.is_absolute()) {
        return d;
    }
    let own = config_home().join("quickshell").join("vyntaris");
    if own.join("shell.qml").exists() { own } else { PathBuf::from("/etc/xdg/quickshell/vyntaris") }
}
