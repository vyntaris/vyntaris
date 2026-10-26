use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const NAME: &str = "Vyntaris";

fn rgb(hex: &str) -> (f64, f64, f64) {
    let h = hex.trim_start_matches('#');
    let c = |i: usize| u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64 / 255.0;
    (c(0), c(2), c(4))
}

fn hex_of(r: f64, g: f64, b: f64) -> String {
    let byte = |v: f64| (v * 255.0).round_ties_even().clamp(0.0, 255.0) as u8;
    format!("#{:02x}{:02x}{:02x}", byte(r), byte(g), byte(b))
}

pub fn rgb_to_hls(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let (maxc, minc) = (r.max(g).max(b), r.min(g).min(b));
    let l = (minc + maxc) / 2.0;
    if minc == maxc {
        return (0.0, l, 0.0);
    }
    let s = if l <= 0.5 { (maxc - minc) / (maxc + minc) } else { (maxc - minc) / (2.0 - maxc - minc) };
    let (rc, gc, bc) = ((maxc - r) / (maxc - minc), (maxc - g) / (maxc - minc), (maxc - b) / (maxc - minc));
    let h = if r == maxc { bc - gc } else if g == maxc { 2.0 + rc - bc } else { 4.0 + gc - rc };
    ((h / 6.0).rem_euclid(1.0), l, s)
}

pub fn hls_to_rgb(h: f64, l: f64, s: f64) -> (f64, f64, f64) {
    if s == 0.0 {
        return (l, l, l);
    }
    let m2 = if l <= 0.5 { l * (1.0 + s) } else { l + s - l * s };
    let m1 = 2.0 * l - m2;
    let v = |hue: f64| {
        let hue = hue.rem_euclid(1.0);
        if hue < 1.0 / 6.0 {
            m1 + (m2 - m1) * hue * 6.0
        } else if hue < 0.5 {
            m2
        } else if hue < 2.0 / 3.0 {
            m1 + (m2 - m1) * (2.0 / 3.0 - hue) * 6.0
        } else {
            m1
        }
    };
    (v(h + 1.0 / 3.0), v(h), v(h - 1.0 / 3.0))
}

fn folder_map(accent: &str) -> [(String, String); 2] {
    let (r, g, b) = rgb(accent);
    let (h, l, s) = rgb_to_hls(r, g, b);
    let (dr, dg, db) = hls_to_rgb(h, l * 0.8, s);
    [("5294e2".into(), accent.to_string()), ("4877b1".into(), hex_of(dr, dg, db))]
}

pub fn folder_colours(svg: &str, map: &[(String, String)]) -> String {
    let b = svg.as_bytes();
    let mut out = String::with_capacity(svg.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'#' && i + 7 <= b.len() && b[i + 1..i + 7].iter().all(u8::is_ascii_hexdigit)
            && !b.get(i + 7).is_some_and(|c| c.is_ascii_alphanumeric() || *c == b'_')
        {
            let code = svg[i + 1..i + 7].to_lowercase();
            if let Some((_, to)) = map.iter().find(|(from, _)| *from == code) {
                out.push_str(to);
                i += 7;
                continue;
            }
        }
        let ch = svg[i..].chars().next().expect("a char");
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn theme_dirs(icons: &Path, theme: &str) -> BTreeMap<String, Vec<String>> {
    let mut sections = BTreeMap::new();
    let mut cur: Option<String> = None;
    for line in fs::read_to_string(icons.join(theme).join("index.theme")).unwrap_or_default().lines() {
        if line.starts_with('[') && line.ends_with(']') {
            let name = line[1..line.len() - 1].to_string();
            sections.insert(name.clone(), Vec::new());
            cur = Some(name);
        } else if let Some(c) = &cur {
            sections.get_mut(c).expect("its section").push(line.to_string());
        }
    }
    sections.remove("Icon Theme");
    sections
}

fn is_blue(name: &str) -> bool {
    ["folder-blue", "user-blue"].iter().any(|p| name.strip_prefix(p).is_some_and(|rest| rest.is_empty() || rest.starts_with(['-', '.'])))
}

fn is_other_colour(name: &str) -> bool {
    const COLOURS: [&str; 25] = [
        "adwaita", "black", "blue", "bluegrey", "breeze", "brown", "carmine", "cyan", "darkcyan", "deeporange", "green",
        "grey", "indigo", "magenta", "nordic", "orange", "palebrown", "paleorange", "pink", "red", "teal", "violet",
        "white", "yaru", "yellow",
    ];
    ["folder-", "user-"].iter().any(|p| {
        name.strip_prefix(p).is_some_and(|rest| {
            COLOURS.iter().any(|c| rest.strip_prefix(c).is_some_and(|after| after.starts_with(['-', '.'])))
        })
    })
}

fn is_generic(name: &str) -> bool {
    [
        "preferences-", "applications-", "system-", "utilities-", "accessories-", "help-", "internet-", "multimedia-",
        "office-", "graphics-", "development-", "games-", "education-", "science-", "user-",
    ]
    .iter()
    .any(|p| name.starts_with(p))
}

#[derive(Debug, PartialEq)]
enum Keep {
    All,
    Places,
    Installed,
    None,
}

fn keep(dir: &str) -> Keep {
    let small = ["16x16/", "22x22/", "24x24/"].iter().any(|s| dir.starts_with(s));
    if dir.contains("symbolic") {
        Keep::All
    } else if dir.ends_with("/places") {
        Keep::Places
    } else if dir.ends_with("/apps") || dir.ends_with("/categories") {
        Keep::Installed
    } else if dir.ends_with("/actions") || dir.ends_with("/panel") {
        if small { Keep::All } else { Keep::None }
    } else {
        Keep::All
    }
}

fn installed_icons() -> BTreeSet<String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let data_home = std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| format!("{home}/.local/share"));
    let data_dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    let mut dirs: Vec<String> = std::iter::once(data_home.clone()).chain(data_dirs.split(':').map(String::from)).collect();
    dirs.push("/var/lib/flatpak/exports/share".into());
    dirs.push(format!("{data_home}/flatpak/exports/share"));
    let mut out = BTreeSet::new();
    for d in dirs {
        for e in fs::read_dir(Path::new(&d).join("applications")).into_iter().flatten().flatten() {
            out.extend(fs::read_to_string(e.path()).unwrap_or_default().lines().filter_map(icon_of));
        }
    }
    out
}

fn icon_of(line: &str) -> Option<String> {
    let v = line.strip_prefix("Icon=")?.trim();
    let name = v.rsplit('/').next()?;
    let name = name.strip_suffix(".svg").or_else(|| name.strip_suffix(".png")).unwrap_or(name);
    (!name.is_empty()).then(|| name.to_string())
}

fn link(to: &Path, at: &Path) -> bool {
    if let Some(parent) = at.parent() {
        let _ = fs::create_dir_all(parent);
    }
    std::os::unix::fs::symlink(to, at).is_ok()
}

fn link_base(icons: &Path, base: &str, work: &Path, written: &mut BTreeMap<String, Vec<String>>) {
    let sections = theme_dirs(icons, base);
    let wanted = installed_icons();
    let index = fs::read_to_string(icons.join(base).join("index.theme")).unwrap_or_default();
    let listed = index.lines().find_map(|l| l.strip_prefix("Directories=")).unwrap_or_default();
    for dir in listed.split(',').filter(|d| !d.is_empty()) {
        let Ok(real) = fs::canonicalize(icons.join(base).join(dir)) else { continue };
        let at = work.join(dir);
        let kept = match keep(dir) {
            Keep::None => false,
            Keep::All => link(&real, &at),
            Keep::Places | Keep::Installed => {
                let places = keep(dir) == Keep::Places;
                let _ = fs::create_dir_all(&at);
                for e in fs::read_dir(&real).into_iter().flatten().flatten() {
                    let file = e.file_name().to_string_lossy().to_string();
                    let name = file.strip_suffix(".svg").unwrap_or(&file);
                    let take = if places {
                        !is_other_colour(&file) && !at.join(&file).exists()
                    } else {
                        wanted.contains(name) || is_generic(name)
                    };
                    if let (true, Ok(to)) = (take, fs::canonicalize(e.path())) {
                        link(&to, &at.join(&file));
                    }
                }
                true
            }
        };
        if kept {
            written.entry(dir.to_string()).or_insert_with(|| sections.get(dir).cloned().unwrap_or_default());
        }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [out_root, base, accent] = &args[..] else {
        eprintln!("icon-theme OUT_ROOT BASE_THEME ACCENT(#rrggbb)");
        std::process::exit(2);
    };
    let icons = PathBuf::from(std::env::var("VYNTARIS_ICONS").unwrap_or_else(|_| "/usr/share/icons".into()));
    let out_root = Path::new(out_root);
    let written_from = written_from(&icons, base, accent);
    let mark = out_root.join(NAME).join(".written-from");
    if fs::read_to_string(&mark).is_ok_and(|was| was == written_from) && out_root.join(NAME).join("index.theme").is_file() {
        println!("{}: as it was", out_root.join(NAME).display());
        return;
    }
    let map = folder_map(accent);
    let source = (base.starts_with("Papirus") && icons.join("Papirus").is_dir()).then_some("Papirus");
    let work = out_root.join(format!(".{NAME}.new"));
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).expect("the work folder");
    let mut written: BTreeMap<String, Vec<String>> = BTreeMap::new();

    if let Some(source) = source {
        let sections = theme_dirs(&icons, source);
        let root = icons.join(source);
        for size in fs::read_dir(&root).into_iter().flatten().flatten() {
            let places = size.path().join("places");
            let Ok(entries) = fs::read_dir(&places) else { continue };
            let subdir = format!("{}/places", size.file_name().to_string_lossy());
            for e in entries.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                let Ok(real) = fs::canonicalize(e.path()) else { continue };
                let real_name = real.file_name().map(|f| f.to_string_lossy().to_string()).unwrap_or_default();
                if is_blue(&name) || !is_blue(&real_name) || !real_name.ends_with(".svg") || !real.is_file() {
                    continue;
                }
                let Ok(svg) = fs::read_to_string(&real) else { continue };
                let dir = work.join(&subdir);
                let _ = fs::create_dir_all(&dir);
                if fs::write(dir.join(&name), folder_colours(&svg, &map)).is_ok() {
                    written.insert(subdir.clone(), sections.get(&subdir).cloned().unwrap_or_default());
                }
            }
        }
    }

    let inherits = if source.is_some() && icons.join(base).is_dir() {
        link_base(&icons, base, &work, &mut written);
        "Adwaita,hicolor".to_string()
    } else {
        format!("{base},hicolor")
    };
    let mut index = format!(
        "[Icon Theme]\nName={NAME}\nComment={base}, its folders in the accent (written by the Vyntaris shell)\nInherits={inherits}\nDirectories={}\n\n",
        written.keys().cloned().collect::<Vec<_>>().join(",")
    );
    for (d, lines) in &written {
        index.push_str(&format!("[{d}]\n{}\n\n", lines.join("\n")));
    }
    fs::write(work.join("index.theme"), index).expect("index.theme");
    let _ = fs::write(work.join(".written-from"), &written_from);
    for tool in ["gtk4-update-icon-cache", "gtk-update-icon-cache"] {
        if Command::new(tool).args(["-q", "-f", "-t"]).arg(&work).status().is_ok_and(|s| s.success()) {
            break;
        }
    }

    let final_dir = out_root.join(NAME);
    let old = out_root.join(format!(".{NAME}.old"));
    let _ = fs::remove_dir_all(&old);
    if final_dir.is_dir() {
        let _ = fs::rename(&final_dir, &old);
    }
    fs::rename(&work, &final_dir).expect("the theme in place");
    let _ = fs::remove_dir_all(&old);
    println!("{}: written", final_dir.display());
}

const HOW: u32 = 1;
fn written_from(icons: &Path, base: &str, accent: &str) -> String {
    let installed = |theme: &str| {
        fs::metadata(icons.join(theme).join("index.theme"))
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_secs())
    };
    let apps: Vec<String> = installed_icons().into_iter().collect();
    format!("{HOW} {base} {} Papirus {} {accent} {}\n", installed(base), installed("Papirus"), apps.join(","))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_blues_become_the_accent() {
        let map = folder_map("#cba6f7");
        let svg = r##"<path fill="#5294E2"/><path fill="#4877b1"/><path fill="#5294e2aa"/><path fill="#ffffff"/>"##;
        let out = folder_colours(svg, &map);
        assert!(out.contains("fill=\"#cba6f7\""));
        assert!(out.contains(&format!("fill=\"{}\"", map[1].1)));
        assert!(out.contains("#5294e2aa"), "not a whole colour: left");
        assert!(is_blue("folder-blue.svg") && is_blue("user-blue-home.svg") && !is_blue("folder-bluegrass.svg"));
    }

    #[test]
    fn what_of_papirus_is_kept() {
        assert_eq!(keep("16x16/symbolic/actions"), Keep::All);
        assert_eq!(keep("symbolic/actions"), Keep::All);
        assert_eq!(keep("48x48/mimetypes"), Keep::All);
        assert_eq!(keep("24x24/panel"), Keep::All);
        assert_eq!(keep("48x48/actions"), Keep::None);
        assert_eq!(keep("64x64/places"), Keep::Places);
        assert_eq!(keep("48x48/apps"), Keep::Installed);
        assert!(is_other_colour("folder-red-music.svg") && is_other_colour("user-teal.svg") && is_other_colour("folder-blue.svg"));
        assert!(!is_other_colour("folder-music.svg") && !is_other_colour("folder.svg") && !is_other_colour("user-home.svg"));
        assert!(!is_other_colour("folder-redhat.svg"), "a word that starts like a colour isn't one");
        assert!(is_generic("preferences-system") && !is_generic("firefox"));
        assert_eq!(icon_of("Icon=org.gnome.Calculator").as_deref(), Some("org.gnome.Calculator"));
        assert_eq!(icon_of("Icon=/opt/app/icon.png").as_deref(), Some("icon"));
        assert_eq!(icon_of("Icon="), None);
        assert_eq!(icon_of("Name=x"), None);
    }
}
