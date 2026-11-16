use std::collections::BTreeMap;
use std::sync::OnceLock;

const PALETTES_JS: &str = include_str!("../../../config/quickshell/config/Palettes.js");
const SHAPE_JS: &str = include_str!("../../../config/quickshell/components/LogoShape.js");

pub type Palette = BTreeMap<String, String>;

pub fn palettes() -> &'static BTreeMap<String, Palette> {
    static ALL: OnceLock<BTreeMap<String, Palette>> = OnceLock::new();
    ALL.get_or_init(|| {
        let mut out = BTreeMap::new();
        let mut rest = PALETTES_JS;
        while let Some(open) = rest.find('{') {
            let before = rest[..open].trim_end();
            let name = before.strip_suffix(':').map_or("", |b| {
                let b = b.trim_end();
                &b[b.rfind(|c: char| !(c.is_alphanumeric() || c == '_')).map_or(0, |i| i + 1)..]
            });
            if name.is_empty() {
                rest = &rest[open + 1..];
                continue;
            }
            let Some(close) = rest[open..].find('}') else { break };
            let body = &rest[open + 1..open + close];
            let colours: Palette = body
                .split(',')
                .filter_map(|entry| {
                    let (k, v) = entry.split_once(':')?;
                    let v = v.trim().trim_matches('"');
                    is_hex(v).then(|| (k.trim().to_string(), v.to_lowercase()))
                })
                .collect();
            if colours.contains_key("base") && !name.is_empty() {
                out.insert(name.to_string(), colours);
            }
            rest = &rest[open + close + 1..];
        }
        out
    })
}

pub fn palette(flavour: &str) -> &'static Palette {
    palettes().get(flavour).unwrap_or_else(|| &palettes()["mocha"])
}

pub fn shape() -> &'static serde_json::Value {
    static SHAPE: OnceLock<serde_json::Value> = OnceLock::new();
    SHAPE.get_or_init(|| {
        let json = &SHAPE_JS[SHAPE_JS.find('{').unwrap_or(0)..SHAPE_JS.rfind('}').map_or(0, |i| i + 1)];
        serde_json::from_str(json).unwrap_or_default()
    })
}

pub fn partners() -> &'static BTreeMap<String, String> {
    static PAIRS: OnceLock<BTreeMap<String, String>> = OnceLock::new();
    PAIRS.get_or_init(|| shape().get("partners").cloned().and_then(|p| serde_json::from_value(p).ok()).unwrap_or_default())
}

pub fn mix(a: &str, b: &str, t: f64) -> (f64, f64, f64) {
    let (x, y) = (rgb(a), rgb(b));
    (x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t)
}

pub fn is_hex(s: &str) -> bool {
    s.len() == 7 && s.starts_with('#') && s[1..].chars().all(|c| c.is_ascii_hexdigit())
}

pub fn rgb(hex: &str) -> (f64, f64, f64) {
    let c = |i: usize| u8::from_str_radix(&hex[i..i + 2], 16).unwrap_or(0) as f64 / 255.0;
    (c(1), c(3), c(5))
}

pub fn hsl(hex: &str) -> (f64, f64, f64) {
    let (r, g, b) = rgb(hex);
    let (hi, lo) = (r.max(g).max(b), r.min(g).min(b));
    let (l, d) = ((hi + lo) / 2.0, hi - lo);
    let (mut h, mut s) = (0.0, 0.0);
    if d > 0.0 {
        s = d / (1.0 - (2.0 * l - 1.0).abs());
        h = if hi == r {
            60.0 * (((g - b) / d) % 6.0)
        } else if hi == g {
            60.0 * ((b - r) / d + 2.0)
        } else {
            60.0 * ((r - g) / d + 4.0)
        };
    }
    ((h + 360.0) % 360.0, s, l)
}

pub fn from_hsl(h: f64, s: f64, l: f64) -> String {
    let h = ((h % 360.0) + 360.0) % 360.0;
    let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    let m = l - c / 2.0;
    let (r, g, b) = if h < 60.0 {
        (c, x, 0.0)
    } else if h < 120.0 {
        (x, c, 0.0)
    } else if h < 180.0 {
        (0.0, c, x)
    } else if h < 240.0 {
        (0.0, x, c)
    } else if h < 300.0 {
        (x, 0.0, c)
    } else {
        (c, 0.0, x)
    };
    let byte = |v: f64| ((v + m) * 255.0 + 0.5).floor().clamp(0.0, 255.0) as u8;
    format!("#{:02x}{:02x}{:02x}", byte(r), byte(g), byte(b))
}

pub fn partner_of(colour: &str) -> String {
    let (h, s, l) = hsl(colour);
    from_hsl(h - 45.0, s, l)
}

pub fn accent(pal: &Palette, name: &str) -> (String, String) {
    if is_hex(name) {
        let a = name.to_lowercase();
        let p = partner_of(&a);
        return (a, p);
    }
    let name = if pal.contains_key(name) { name } else { "blue" };
    let partner = partners().get(name).map_or("blue", String::as_str);
    (pal[name].clone(), pal.get(partner).cloned().unwrap_or_else(|| pal["blue"].clone()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_flavours_are_read() {
        for f in ["latte", "frappe", "macchiato", "mocha"] {
            assert!(palettes().contains_key(f), "{f}");
        }
        assert_eq!(palette("mocha")["mauve"], "#cba6f7");
        assert_eq!(palette("nothing")["base"], palette("mocha")["base"]);
    }

    #[test]
    fn an_accent_by_name_and_by_colour() {
        let mocha = palette("mocha");
        assert_eq!(accent(mocha, "mauve"), ("#cba6f7".into(), mocha["blue"].clone()));
        assert_eq!(accent(mocha, "nonsense").0, mocha["blue"]);
        let (a, p) = accent(mocha, "#ff0000");
        assert!(is_hex(&a) && is_hex(&p) && a != p);
    }
}

/// The accents a palette has by name, as Palettes.js lists them (accentNames).
pub fn accent_names() -> &'static Vec<String> {
    static NAMES: OnceLock<Vec<String>> = OnceLock::new();
    NAMES.get_or_init(|| {
        let Some(at) = PALETTES_JS.find("var accentNames") else { return vec![] };
        let rest = &PALETTES_JS[at..];
        let (Some(open), Some(close)) = (rest.find('['), rest.find(']')) else { return vec![] };
        rest[open + 1..close].split(',').map(|n| n.trim().trim_matches('"').to_string()).filter(|n| !n.is_empty()).collect()
    })
}

fn oklab(hex: &str) -> [f64; 3] {
    let (r, g, b) = rgb(hex);
    let lin = |v: f64| if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) };
    let (r, g, b) = (lin(r), lin(g), lin(b));
    let l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b).cbrt();
    let m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b).cbrt();
    let s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b).cbrt();
    [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
}

/// The palette's named accent closest to a colour (Palettes.js nearest()).
pub fn nearest(flavour: &str, colour: &str) -> String {
    let pal = palette(flavour);
    if !is_hex(colour) {
        return if pal.contains_key(colour) { colour.to_string() } else { "blue".to_string() };
    }
    let t = oklab(colour);
    let mut best = ("mauve".to_string(), f64::INFINITY);
    for name in accent_names() {
        let Some(hex) = pal.get(name) else { continue };
        let p = oklab(hex);
        let d = 0.3 * (p[0] - t[0]).powi(2) + (p[1] - t[1]).powi(2) + (p[2] - t[2]).powi(2);
        if d < best.1 {
            best = (name.clone(), d);
        }
    }
    best.0
}
