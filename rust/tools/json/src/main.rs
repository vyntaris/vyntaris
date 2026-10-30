use regex::Regex;
use serde_json::{Value, json};
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

fn greeter(args: &[String]) -> Value {
    let mut stdin = String::new();
    let _ = std::io::stdin().read_to_string(&mut stdin);
    let s: Value = serde_json::from_str(&stdin).ok().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let (t, b, a) = (section(&s, "theme"), section(&s, "bar"), section(&s, "accessibility"));
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();
    let full = if arg(3).is_empty() { arg(0) } else { arg(3) };
    json!({
        "user": arg(0), "session": ["vyntaris-session"], "wallpaper": arg(1), "face": arg(2), "fullName": full,
        "flavor": or(t, "flavor", json!("mocha")), "accent": or(t, "accent", json!("mauve")), "accentLight": or(t, "accentLight", json!("mauve")),
        "font": or(t, "fontFamily", json!("Inter")), "monoFont": or(t, "monoFamily", json!("JetBrains Mono")),
        "fontSize": or(t, "fontSize", json!(13)), "animationSpeed": or(t, "animationSpeed", json!(1)),
        "animationStyle": or(t, "animationStyle", json!("snappy")), "highContrast": or(a, "highContrast", json!(false)),
        "barHeight": or(b, "height", json!(28)), "endCurve": or(b, "endCurve", json!(16)),
        "corners": or(b, "corners", json!("round")), "notchStyle": or(b, "notchStyle", json!("slant")),
        "flatIsland": or(b, "flatIsland", json!(false)), "endCorners": or(b, "endCorners", json!(false)),
        "inside": or(b, "inside", json!("rounded")),
        "clockFormat": or(b, "clockFormat", json!("HH:mm")),
    })
}

fn splash(path: &str) -> Option<String> {
    let t: Value = serde_json::from_str(&fs::read_to_string(path).ok()?).ok()?;
    let word = Regex::new(r"^[a-z]+$").unwrap();
    let accent_ok = Regex::new(r"^([a-z]+|#[0-9a-fA-F]{6})$").unwrap();
    let f = t.get("flavor").and_then(Value::as_str).unwrap_or("mocha");
    let a = t.get("accent").and_then(Value::as_str).unwrap_or("mauve");
    let f = if f == "latte" || !word.is_match(f) { "mocha" } else { f };
    let a = if accent_ok.is_match(a) { a } else { "mauve" };
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

fn from_base64(text: &[u8]) -> Option<Vec<u8>> {
    let value = |c: u8| match c {
        b'A'..=b'Z' => Some(c - b'A'),
        b'a'..=b'z' => Some(c - b'a' + 26),
        b'0'..=b'9' => Some(c - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    };
    let mut out = Vec::with_capacity(text.len() / 4 * 3);
    let (mut bits, mut have) = (0u32, 0);
    for &c in text.iter().filter(|c| **c != b'=') {
        bits = (bits << 6) | value(c)? as u32;
        have += 6;
        if have >= 8 {
            have -= 8;
            out.push((bits >> have) as u8);
        }
    }
    Some(out)
}

struct Plist<'a> {
    data: &'a [u8],
    table: usize,
    offset_size: usize,
    ref_size: usize,
    objects: usize,
}

impl Plist<'_> {
    fn uint(bytes: &[u8]) -> usize {
        bytes.iter().fold(0usize, |n, b| n.wrapping_shl(8) | *b as usize)
    }

    fn object(&self, index: usize, depth: usize) -> Option<Value> {
        if index >= self.objects || depth > 16 {
            return None;
        }
        let at = self.table.checked_add(index.checked_mul(self.offset_size)?)?;
        let start = Self::uint(self.data.get(at..at.checked_add(self.offset_size)?)?);
        let marker = *self.data.get(start)?;
        let (kind, low) = (marker >> 4, (marker & 15) as usize);
        let (count, body) = if low == 15 && kind >= 5 {
            let head = *self.data.get(start + 1)?;
            let width = 1usize.checked_shl((head & 15) as u32)?;
            (Self::uint(self.data.get(start + 2..start + 2 + width)?), start + 2 + width)
        } else {
            (low, start + 1)
        };
        let refs = |at: usize, n: usize| -> Option<Vec<usize>> {
            let bytes = self.data.get(at..at.checked_add(n.checked_mul(self.ref_size)?)?)?;
            Some(bytes.chunks(self.ref_size).map(Self::uint).collect())
        };
        match kind {
            0x1 => {
                let width = 1usize.checked_shl(low as u32)?;
                Some(json!(Self::uint(self.data.get(start + 1..start + 1 + width)?)))
            }
            0x2 => match low {
                2 => Some(json!(f32::from_be_bytes(self.data.get(start + 1..start + 5)?.try_into().ok()?))),
                3 => Some(json!(f64::from_be_bytes(self.data.get(start + 1..start + 9)?.try_into().ok()?))),
                _ => None,
            },
            0x5 => Some(json!(String::from_utf8_lossy(self.data.get(body..body.checked_add(count)?)?))),
            0xA => {
                let items = refs(body, count)?;
                items.into_iter().map(|i| self.object(i, depth + 1)).collect::<Option<Vec<_>>>().map(Value::Array)
            }
            0xD => {
                let keys = refs(body, count)?;
                let values = refs(body.checked_add(count.checked_mul(self.ref_size)?)?, count)?;
                let mut map = serde_json::Map::new();
                for (k, v) in keys.into_iter().zip(values) {
                    if let Value::String(key) = self.object(k, depth + 1)? {
                        map.insert(key, self.object(v, depth + 1)?);
                    }
                }
                Some(Value::Object(map))
            }
            _ => Some(Value::Null),
        }
    }
}

fn parse_plist(data: &[u8]) -> Option<Value> {
    if !data.starts_with(b"bplist00") || data.len() < 40 {
        return None;
    }
    let tail = &data[data.len() - 32..];
    let plist = Plist {
        data,
        offset_size: tail[6] as usize,
        ref_size: tail[7] as usize,
        objects: Plist::uint(&tail[8..16]),
        table: Plist::uint(&tail[24..32]),
    };
    if plist.offset_size == 0 || plist.ref_size == 0 {
        return None;
    }
    plist.object(Plist::uint(&tail[16..24]), 0)
}

fn minute_of_sun(altitude: f64, azimuth: f64) -> f64 {
    let rise = (altitude / 60.0).clamp(-1.0, 1.0).asin() / std::f64::consts::PI * 720.0;
    (if azimuth < 180.0 { 360.0 + rise } else { 1080.0 - rise }).rem_euclid(1440.0)
}

fn heic_schedule(kind: &str, plist: &Value) -> Option<Value> {
    let number = |v: &Value, key: &str| v.get(key).and_then(Value::as_f64);
    let list = plist.get(if kind == "h24" { "ti" } else { "si" })?.as_array()?;
    let mut entries: Vec<(f64, u64)> = list
        .iter()
        .filter_map(|e| {
            let minute = if kind == "h24" { number(e, "t")? * 1440.0 } else { minute_of_sun(number(e, "a")?, number(e, "z")?) };
            Some((minute, e.get("i")?.as_u64()?))
        })
        .collect();
    entries.sort_by(|a, b| a.0.total_cmp(&b.0));
    (!entries.is_empty()).then(|| Value::Array(entries.iter().map(|(m, i)| json!({ "m": m.round(), "i": i })).collect()))
}

fn heic_file_schedule(path: &str) -> Option<Value> {
    let bytes = fs::read(path).ok()?;
    let found = regex::bytes::Regex::new(r#"apple_desktop:(h24|solar)(?:="|>)([A-Za-z0-9+/=]+)"#).unwrap();
    let m = found.captures(&bytes)?;
    let kind = String::from_utf8_lossy(&m[1]).to_string();
    heic_schedule(&kind, &parse_plist(&from_base64(&m[2])?)?)
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
        ["heic-schedule", file] => heic_file_schedule(file).map(|s| println!("{s}")).is_some(),
        ["guard-status", out] => guard_status(out).is_ok(),
        ["merge-actions", uca, extra] => merge_actions(uca, extra).is_ok(),
        _ => {
            eprintln!("json get|palette|snapshots|greeter|splash|heic-schedule|guard-status|merge-actions …");
            false
        }
    };
    std::process::exit(if ok { 0 } else { 1 });
}

#[cfg(test)]
mod heic_tests {
    use super::*;

    #[test]
    fn reads_a_schedule_from_a_binary_plist() {
        let data = [98, 112, 108, 105, 115, 116, 48, 48, 209, 1, 2, 82, 116, 105, 162, 3, 8, 210, 4, 5, 6, 7, 81, 105, 81, 116, 16, 2, 35, 63, 224, 0, 0, 0, 0, 0, 0, 210, 4, 5, 9, 10, 16, 1, 35, 0, 0, 0, 0, 0, 0, 0, 0, 8, 11, 14, 17, 22, 24, 26, 28, 37, 42, 44, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 53];
        let plist = parse_plist(&data).expect("a plist");
        let s = heic_schedule("h24", &plist).expect("a schedule");
        assert_eq!(s, json!([{ "m": 0.0, "i": 1 }, { "m": 720.0, "i": 2 }]));
    }

    #[test]
    fn what_is_not_a_plist_is_refused() {
        assert!(parse_plist(b"not a plist at all, not even close to one").is_none());
        let mut broken = [98, 112, 108, 105, 115, 116, 48, 48, 209, 1, 2, 82, 116, 105, 162, 3, 8, 210, 4, 5, 6, 7, 81, 105, 81, 116, 16, 2, 35, 63, 224, 0, 0, 0, 0, 0, 0, 210, 4, 5, 9, 10, 16, 1, 35, 0, 0, 0, 0, 0, 0, 0, 0, 8, 11, 14, 17, 22, 24, 26, 28, 37, 42, 44, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 53].to_vec();
        let at = broken.len() - 8;
        broken[at..].fill(255);
        assert!(parse_plist(&broken).is_none());
    }

    #[test]
    fn base64_and_the_sun() {
        assert_eq!(from_base64(b"aGVsbG8=").unwrap(), b"hello");
        assert_eq!(minute_of_sun(0.0, 90.0), 360.0);
        assert_eq!(minute_of_sun(60.0, 180.0), 720.0);
        assert_eq!(minute_of_sun(0.0, 270.0), 1080.0);
    }
}
