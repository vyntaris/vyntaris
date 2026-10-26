use serde_json::{Value, json};
use std::collections::HashSet;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;

const THEME: &str = "/usr/share/icons/Papirus/64x64/apps";
const XML_NS: &str = "http://www.w3.org/XML/1998/namespace";

const GROUPS: &[(&str, &str)] = &[
    ("Game", "games"), ("Office", "office"), ("Development", "development"), ("Graphics", "graphics"),
    ("AudioVideo", "media"), ("Audio", "media"), ("Video", "media"), ("Network", "internet"),
    ("Education", "education"), ("Science", "education"), ("Utility", "utilities"),
    ("System", "system"), ("Settings", "system"),
];

fn installed() -> HashSet<String> {
    Command::new("pacman").arg("-Qq").output().map(|o| String::from_utf8_lossy(&o.stdout).split_whitespace().map(str::to_string).collect()).unwrap_or_default()
}

fn squash(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn untranslated(n: &roxmltree::Node) -> bool {
    n.attribute((XML_NS, "lang")).is_none()
}

fn children<'a, 'i>(n: roxmltree::Node<'a, 'i>, tag: &'a str) -> impl Iterator<Item = roxmltree::Node<'a, 'i>> + 'a {
    n.children().filter(move |c| c.has_tag_name(tag))
}

fn text(c: roxmltree::Node, tag: &str) -> String {
    children(c, tag).find(|e| untranslated(e) && e.text().is_some_and(|t| !t.is_empty())).map(|e| squash(e.text().unwrap_or(""))).unwrap_or_default()
}

fn all_text(n: roxmltree::Node) -> String {
    n.descendants().filter(|d| d.is_text()).filter_map(|d| d.text()).collect()
}

fn description(c: roxmltree::Node) -> String {
    let Some(d) = children(c, "description").next() else { return String::new() };
    let paras: Vec<String> = d.children().filter(|p| p.is_element() && p.has_tag_name("p") && untranslated(p)).map(|p| squash(&all_text(p))).filter(|p| !p.is_empty()).collect();
    paras.join(" ").chars().take(600).collect()
}

fn group(c: roxmltree::Node) -> &'static str {
    let cats: Vec<&str> = c.descendants().filter(|e| e.has_tag_name("category")).filter_map(|e| e.text()).collect();
    GROUPS.iter().find(|(name, _)| cats.contains(name)).map_or("utilities", |(_, g)| g)
}

fn read_xml(path: &Path) -> Option<String> {
    let bytes = fs::read(path).ok()?;
    let mut out = String::new();
    if path.extension().is_some_and(|e| e == "gz") {
        flate2::read::GzDecoder::new(&bytes[..]).read_to_string(&mut out).ok()?;
    } else {
        out = String::from_utf8(bytes).ok()?;
    }
    Some(out)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(out) = args.first().map(PathBuf::from) else {
        eprintln!("store-index OUT_JSON [--installed-only]");
        std::process::exit(2);
    };
    let pac = installed();
    let write = |cat: &Value| {
        let tmp = out.with_extension("json.new");
        fs::write(&tmp, serde_json::to_string(cat).expect("json")).expect("the catalogue");
        fs::rename(tmp, &out).expect("the catalogue in place");
    };

    if args.iter().any(|a| a == "--installed-only") {
        let Ok(mut cat) = fs::read_to_string(&out).map_err(|_| ()).and_then(|s| serde_json::from_str::<Value>(&s).map_err(|_| ())) else { return };
        if let Some(apps) = cat.get_mut("apps").and_then(Value::as_array_mut) {
            for a in apps {
                let on = a.get("pkg").and_then(Value::as_str).is_some_and(|p| pac.contains(p));
                a["installed"] = json!(on);
            }
        }
        write(&cat);
        return;
    }

    let swcatalog = PathBuf::from(std::env::var("VYNTARIS_SWCATALOG").unwrap_or_else(|_| "/usr/share/swcatalog".into()));
    let cache = vyntaris_core::paths::cache_home().join("vyntaris").join("store-icons");
    let _ = fs::create_dir_all(&cache);
    let mut apps: Vec<Value> = Vec::new();
    let mut to_convert: Vec<PathBuf> = Vec::new();
    let mut files: Vec<PathBuf> = fs::read_dir(swcatalog.join("xml")).into_iter().flatten().flatten().map(|e| e.path())
        .filter(|p| p.to_string_lossy().ends_with(".xml.gz")).collect();
    files.sort();

    for xml_path in files {
        let repo = xml_path.file_name().and_then(|f| f.to_str()).and_then(|f| f.split('.').next()).unwrap_or("").to_string();
        let Some(xml) = read_xml(&xml_path) else { continue };
        let Ok(doc) = roxmltree::Document::parse_with_options(&xml, roxmltree::ParsingOptions { allow_dtd: true, ..Default::default() }) else { continue };
        for c in doc.descendants().filter(|n| n.has_tag_name("component") && n.attribute("type") == Some("desktop-application")) {
            let pkg = children(c, "pkgname").next().and_then(|e| e.text()).unwrap_or("").trim().to_string();
            let name = text(c, "name");
            if pkg.is_empty() || name.is_empty() {
                continue;
            }
            let icons: Vec<roxmltree::Node> = children(c, "icon").collect();
            let stock = icons.iter().find(|i| i.attribute("type") == Some("stock") && i.text().is_some_and(|t| !t.is_empty())).and_then(|i| i.text()).unwrap_or("");
            let mut icon = String::new();
            if !stock.is_empty() && Path::new(&format!("{THEME}/{stock}.svg")).exists() {
                icon = format!("{THEME}/{stock}.svg");
            } else if let Some(cached) = icons.iter().find(|i| i.attribute("type") == Some("cached") && i.text().is_some_and(|t| !t.is_empty())).and_then(|i| i.text()) {
                let png_name = match cached.rfind('.') {
                    Some(i) if cached[i + 1..].chars().all(|c| c.is_alphanumeric() || c == '_') && i + 1 < cached.len() => format!("{}.png", &cached[..i]),
                    _ => cached.to_string(),
                };
                let png = cache.join(png_name);
                let src = ["128x128", "64x64", "48x48"].iter().map(|size| swcatalog.join(format!("icons/archlinux-arch-{repo}/{size}/{cached}"))).find(|p| p.exists());
                if let Some(src) = src {
                    icon = png.to_string_lossy().to_string();
                    if !png.exists() {
                        to_convert.push(src);
                    }
                }
            }
            if icon.is_empty() && !stock.is_empty() {
                icon = format!("theme:{stock}");
            }
            let id = children(c, "id").next().and_then(|e| e.text()).filter(|t| !t.is_empty()).map(str::to_string).unwrap_or_else(|| pkg.clone());
            apps.push(json!({
                "id": id, "name": name, "summary": text(c, "summary"), "desc": description(c), "source": "arch",
                "installed": pac.contains(&pkg), "pkg": pkg, "icon": icon, "group": group(c),
            }));
        }
    }
    apps.sort_by_cached_key(|a| a["name"].as_str().unwrap_or("").to_lowercase());
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    write(&json!({ "time": now, "apps": apps }));
    println!("{} apps, {} icons to convert", apps.len(), to_convert.len());

    for batch in to_convert.chunks(200) {
        let _ = Command::new("magick").args(["mogrify", "-path"]).arg(&cache).args(["-format", "png"]).args(batch).output();
    }
}
