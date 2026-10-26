use regex::Regex;
use serde_json::{Map, Value, json};
use std::fs;
use std::io::Read;
use std::path::Path;

fn load(path: &str) -> Value {
    fs::read_to_string(path).ok().and_then(|s| serde_json::from_str(&s).ok()).filter(Value::is_object).unwrap_or_else(|| json!({}))
}

fn section<'a>(v: &'a Value, key: &str) -> &'a Value {
    static EMPTY: Value = Value::Null;
    v.get(key).filter(|s| s.is_object()).unwrap_or(&EMPTY)
}

fn or(v: &Value, key: &str, default: Value) -> Value {
    v.get(key).cloned().unwrap_or(default)
}

fn text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

fn palette_only(text: &str) -> Value {
    let Ok(Value::Object(p)) = serde_json::from_str::<Value>(text) else { return Value::Null };
    let name = Regex::new(r"^[a-z0-9]{2,12}$").unwrap();
    let colour = Regex::new(r"^#[0-9a-fA-F]{6,8}$").unwrap();
    let kept: Map<String, Value> = p.into_iter().filter(|(k, v)| name.is_match(k) && v.as_str().is_some_and(|c| colour.is_match(c))).collect();
    if kept.is_empty() { Value::Null } else { Value::Object(kept) }
}

fn greeter(args: &[String]) -> Value {
    let mut stdin = String::new();
    let _ = std::io::stdin().read_to_string(&mut stdin);
    let s: Value = serde_json::from_str(&stdin).ok().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let (t, b, a) = (section(&s, "theme"), section(&s, "bar"), section(&s, "accessibility"));
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();
    let full = if arg(3).is_empty() { arg(0) } else { arg(3) };
    json!({
        "user": arg(0), "session": ["vyntaris-session"], "wallpaper": arg(1), "face": arg(2), "fullName": full,
        "palette": if t.get("wallpaperTint").is_some_and(|v| v.as_bool().unwrap_or(false)) { palette_only(&arg(4)) } else { Value::Null },
        "flavor": or(t, "flavor", json!("mocha")), "accent": or(t, "accent", json!("blue")), "accentLight": or(t, "accentLight", json!("sky")),
        "panelOpacity": or(t, "panelOpacity", json!(1)), "font": or(t, "fontFamily", json!("Inter")), "monoFont": or(t, "monoFamily", json!("JetBrains Mono")),
        "fontSize": or(t, "fontSize", json!(13)), "animationSpeed": or(t, "animationSpeed", json!(1)),
        "animationStyle": or(t, "animationStyle", json!("snappy")), "highContrast": or(a, "highContrast", json!(false)),
        "barHeight": or(b, "height", json!(28)), "endCurve": or(b, "endCurve", json!(16)),
        "corners": or(b, "corners", json!("round")), "notchStyle": or(b, "notchStyle", json!("classic")),
        "flatIsland": or(b, "flatIsland", json!(false)), "endCorners": or(b, "endCorners", json!(true)),
        "inside": or(b, "inside", json!("rounded")),
        "clockFormat": or(b, "clockFormat", json!("HH:mm")),
    })
}

fn splash(path: &str) -> Option<String> {
    let t: Value = serde_json::from_str(&fs::read_to_string(path).ok()?).ok()?;
    let word = Regex::new(r"^[a-z]+$").unwrap();
    let accent_ok = Regex::new(r"^([a-z]+|#[0-9a-fA-F]{6})$").unwrap();
    let f = t.get("flavor").and_then(Value::as_str).unwrap_or("mocha");
    let a = t.get("accent").and_then(Value::as_str).unwrap_or("blue");
    let f = if f == "latte" || !word.is_match(f) { "mocha" } else { f };
    let a = if accent_ok.is_match(a) { a } else { "blue" };
    Some(format!("{f} {a}"))
}

fn snapshots(dir: &str) {
    let mut infos: Vec<_> = fs::read_dir(dir).into_iter().flatten().flatten().map(|e| e.path().join("info.json")).filter(|p| p.is_file()).collect();
    infos.sort();
    let clean = |v: &Value| text(v).replace(['\t', '\n'], " ");
    for info in infos {
        let i = load(&info.to_string_lossy());
        let name = info.parent().and_then(Path::file_name).map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        println!("{name}\t{}\t{}", clean(i.get("tags").unwrap_or(&json!(""))), clean(i.get("comments").unwrap_or(&json!(""))));
    }
}

fn guard_status(out: &str) -> std::io::Result<()> {
    let env = |k: &str| std::env::var(k).unwrap_or_default();
    let last = fs::read_to_string(env("LAST_FILE")).ok().map(|s| {
        s.lines().filter_map(|l| l.split_once('=')).map(|(k, v)| (k.to_string(), v.to_string())).collect::<std::collections::HashMap<_, _>>()
    });
    let why = env("WHY");
    let point = env("POINT_NAME");
    let status = json!({
        "protected": why.is_empty(),
        "reason": why,
        "point": if point.is_empty() { Value::Null } else { json!(point) },
        "pending": env("PENDING") == "true",
        "rollback": last.map(|l| json!({ "at": l.get("at").cloned().unwrap_or_default(), "snapshot": l.get("snapshot").cloned().unwrap_or_default() })),
    });
    let tmp = format!("{out}.new");
    fs::write(&tmp, status.to_string())?;
    fs::set_permissions(&tmp, std::os::unix::fs::PermissionsExt::from_mode(0o644))?;
    fs::rename(tmp, out)
}

fn merge_actions(uca: &str, extra: &str) -> std::io::Result<()> {
    let text = fs::read_to_string(uca)?;
    let extra = fs::read_to_string(extra)?;
    let action = Regex::new(r"(?s)<action>.*?</action>").unwrap();
    let id = Regex::new(r"(?s)<unique-id>(.*?)</unique-id>").unwrap();
    let ours: Vec<(String, &str)> = action.find_iter(&extra)
        .filter_map(|m| id.captures(m.as_str()).map(|c| (c[1].to_string(), m.as_str()))).collect();
    let mut out = action.replace_all(&text, |m: &regex::Captures| {
        let had = id.captures(&m[0]).map(|c| c[1].to_string()).unwrap_or_default();
        match ours.iter().find(|(i, _)| i.starts_with("shell-") && *i == had) {
            Some((_, now)) => now.to_string(),
            None => m[0].to_string(),
        }
    }).into_owned();
    let new: Vec<&str> = ours.iter().filter(|(i, _)| !text.contains(&format!("<unique-id>{i}</unique-id>"))).map(|(_, a)| *a).collect();
    if !new.is_empty() {
        out = out.replacen("</actions>", &format!("{}\n</actions>", new.join("\n")), 1);
    }
    if out != text {
        fs::write(uca, out)?;
    }
    Ok(())
}

fn riseup_gateways<'a>(eip: &'a Value) -> impl Iterator<Item = &'a Value> {
    eip["gateways"].as_array().into_iter().flatten().filter(|g| {
        g["capabilities"]["transport"].as_array().is_some_and(|t| t.iter().any(|t| t["type"] == "openvpn"))
    })
}

fn riseup_places(eip: &Value) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = riseup_gateways(eip)
        .filter_map(|g| g["location"].as_str())
        .map(|l| {
            let place = &eip["locations"][l];
            (place["name"].as_str().unwrap_or(l).to_string(), place["country_code"].as_str().unwrap_or("").to_string())
        })
        .collect();
    out.sort();
    out.dedup();
    out
}

fn riseup_ovpn(eip: &Value, cert_pem: &str, ca: &str, place: &str) -> Option<String> {
    let block = |kind: &str| Regex::new(&format!(r"(?s)-----BEGIN {kind}-----.*?-----END {kind}-----")).ok()?.find(cert_pem).map(|m| m.as_str().to_string());
    let cert = block("CERTIFICATE")?;
    let key = block("(?:[A-Z]+ )?PRIVATE KEY")?;
    let remotes: Vec<String> = riseup_gateways(eip)
        .filter(|g| g["location"].as_str().map(|l| eip["locations"][l]["name"].as_str().unwrap_or(l)) == Some(place))
        .filter_map(|g| g["ip_address"].as_str())
        .map(|ip| format!("remote {ip} 1194 udp"))
        .collect();
    if remotes.is_empty() || !ca.contains("BEGIN CERTIFICATE") {
        return None;
    }
    let c = &eip["openvpn_configuration"];
    let s = |k: &str, d: &str| c[k].as_str().unwrap_or(d).to_string();
    Some(format!(
        "client\ndev tun\nremote-cert-tls server\ntls-client\nnobind\npersist-key\npersist-tun\n\
         cipher {}\ndata-ciphers {}\nauth {}\ntls-cipher {}\ntls-version-min {}\nkeepalive {}\nverb 3\n\
         {}\nremote-random\n<ca>\n{}\n</ca>\n<cert>\n{cert}\n</cert>\n<key>\n{key}\n</key>\n",
        s("cipher", "AES-256-GCM"),
        s("data-ciphers", "AES-256-GCM"),
        s("auth", "SHA512"),
        s("tls-cipher", "TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384"),
        s("tls-version-min", "1.2"),
        s("keepalive", "10 30"),
        remotes.join("\n"),
        ca.trim(),
    ))
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    let ok = match a.as_slice() {
        ["get", file, path, rest @ ..] => {
            let v = load(file);
            let (sec, key) = path.split_once('.').unwrap_or(("", path));
            let found = if sec.is_empty() { v.get(key) } else { section(&v, sec).get(key) };
            match found {
                Some(v) if !v.is_null() => println!("{}", text(v)),
                _ => println!("{}", rest.first().copied().unwrap_or("")),
            }
            true
        }
        ["palette", flavour, names @ ..] => {
            let p = vyntaris_core::palette::palette(flavour);
            println!("{}", names.iter().map(|n| p.get(*n).cloned().unwrap_or_default()).collect::<Vec<_>>().join(" "));
            true
        }
        ["tr", text, values @ ..] => {
            let mut out = vyntaris_core::i18n::tr(text);
            for (i, v) in values.iter().enumerate() {
                out = out.replace(&format!("{{{i}}}"), v);
            }
            println!("{out}");
            true
        }
        ["riseup-places", eip] => {
            riseup_places(&load(eip)).iter().for_each(|(n, c)| println!("{n}\t{c}"));
            true
        }
        ["riseup-ovpn", eip, cert, ca, place] => {
            let read = |f: &str| fs::read_to_string(f).unwrap_or_default();
            riseup_ovpn(&load(eip), &read(cert), &read(ca), place).map(|o| print!("{o}")).is_some()
        }
        ["snapshots", dir] => {
            snapshots(dir);
            true
        }
        ["greeter", rest @ ..] => {
            println!("{}", serde_json::to_string_pretty(&greeter(&rest.iter().map(|s| s.to_string()).collect::<Vec<_>>())).unwrap_or_default());
            true
        }
        ["splash", file] => splash(file).map(|s| println!("{s}")).is_some(),
        ["guard-status", out] => guard_status(out).is_ok(),
        ["merge-actions", uca, extra] => merge_actions(uca, extra).is_ok(),
        _ => {
            eprintln!("json get|palette|snapshots|greeter|splash|guard-status|merge-actions …");
            false
        }
    };
    std::process::exit(if ok { 0 } else { 1 });
}
