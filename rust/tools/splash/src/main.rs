mod pyrandom;

use cairo::{Context, FillRule, Format, ImageSurface, LinearGradient, Operator, Pattern, RadialGradient, SolidPattern};
use regex::Regex;
use serde_json::{Value, json};
use std::f64::consts::PI;
use std::fs;
use std::path::{Path, PathBuf};
use vyntaris_core::palette::{accent, mix, palette, rgb, shape};

const SPLASH_VERSION: u32 = 1;
const FPS: u32 = 50;
const LOOP: usize = 110;
const INTRO: usize = 130;
const IGNITE: usize = 52;
const ECC: f64 = 0.45;
const TAIL: f64 = 1.9;
const WORD: usize = 72;
const WHITE: &str = "#ffffff";
const SCRIPT_IN: &str = include_str!("../../../../system/plymouth/island.script.in");

type Rgb = (f64, f64, f64);

fn py(x: f64) -> String {
    if x.fract() == 0.0 && x.abs() < 1e16 { format!("{x:.1}") } else { format!("{x}") }
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round_ties_even() / 10.0
}

struct Orbit {
    cx: f64,
    cy: f64,
    rx: f64,
    ry: f64,
    tilt: f64,
    pr: f64,
    width: (f64, f64),
    planet: (f64, f64),
}

struct Splash {
    o: Orbit,
    k: f64,
    acc: Rgb,
    light: Rgb,
    hot: Rgb,
    base: String,
    v_fill: Pattern,
    front_fill: Pattern,
    back_fill: Pattern,
    ring_v: String,
    ring_back: String,
    ring_front: String,
    ring_hide: String,
    ox: f64,
    oy: f64,
    w: i32,
    h: i32,
    times: Vec<f64>,
    turn: f64,
}

fn linear(x0: f64, y0: f64, x1: f64, y1: f64, stops: &[(f64, Rgb, f64)]) -> Pattern {
    let g = LinearGradient::new(x0, y0, x1, y1);
    for (o, c, a) in stops {
        g.add_color_stop_rgba(*o, c.0, c.1, c.2, *a);
    }
    (**g).clone()
}

fn radial(x: f64, y: f64, r: f64, stops: &[(f64, Rgb, f64)]) -> Pattern {
    let g = RadialGradient::new(x, y, 0.0, x, y, r);
    for (o, c, a) in stops {
        g.add_color_stop_rgba(*o, c.0, c.1, c.2, *a);
    }
    (**g).clone()
}

fn solid(c: Rgb, a: f64) -> Pattern {
    (*SolidPattern::from_rgba(c.0, c.1, c.2, a)).clone()
}

fn trace(cr: &Context, d: &str) {
    static CMD: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| Regex::new(r"([MLz])\s*([-\d.]*)\s*([-\d.]*)").unwrap());
    for c in CMD.captures_iter(d) {
        let (x, y) = (c[2].parse::<f64>().unwrap_or(0.0), c[3].parse::<f64>().unwrap_or(0.0));
        match &c[1] {
            "M" => cr.move_to(x, y),
            "L" => cr.line_to(x, y),
            _ => cr.close_path(),
        }
    }
}

fn fill(cr: &Context, d: &str, source: &Pattern) {
    let _ = cr.save();
    trace(cr, d);
    cr.set_fill_rule(FillRule::EvenOdd);
    let _ = cr.set_source(source);
    let _ = cr.fill();
    let _ = cr.restore();
}

fn ease(x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    1.0 - (1.0 - x).powi(3)
}

impl Splash {
    fn spot(&self, t: f64, scale: f64) -> (f64, f64) {
        let o = &self.o;
        let (ex, ey) = (o.rx * scale * t.cos(), o.ry * scale * t.sin());
        (o.cx + ex * o.tilt.cos() - ey * o.tilt.sin(), o.cy + ex * o.tilt.sin() + ey * o.tilt.cos())
    }

    fn near(t: f64) -> f64 {
        1.0 + 0.18 * t.sin()
    }

    fn band(&self, t: f64) -> f64 {
        let (lo, hi) = self.o.width;
        lo + (hi - lo) * ((1.0 - t.cos()) / 2.0).powf(0.9)
    }

    fn planet(&self, cr: &Context, x: f64, y: f64, r: f64, a: f64) {
        let acc = self.acc;
        let _ = cr.set_source(radial(x, y, r * 2.3, &[(0.3, acc, 0.4 * a), (0.55, acc, 0.12 * a), (1.0, acc, 0.0)]));
        cr.arc(x, y, r * 2.3, 0.0, 2.0 * PI);
        let _ = cr.fill();
        let g = RadialGradient::new(x - r * 0.35, y - r * 0.4, 0.0, x - r * 0.35, y - r * 0.4, r * 1.35);
        g.add_color_stop_rgba(0.0, 1.0, 1.0, 1.0, a);
        let m = mix_rgb(acc, (1.0, 1.0, 1.0), 0.5);
        g.add_color_stop_rgba(0.35, m.0, m.1, m.2, a);
        g.add_color_stop_rgba(1.0, acc.0, acc.1, acc.2, a);
        let _ = cr.set_source(&g);
        cr.arc(x, y, r, 0.0, 2.0 * PI);
        let _ = cr.fill();
    }

    fn tail(&self, cr: &Context, t: f64, length: f64, front: bool) {
        let n = 64;
        cr.set_line_cap(cairo::LineCap::Round);
        for glow in [true, false] {
            for i in 0..n {
                let (a, b) = (t - length * i as f64 / n as f64, t - length * (i + 1) as f64 / n as f64);
                if (((a + b) / 2.0).sin() > 0.0) != front {
                    continue;
                }
                let k = 1.0 - i as f64 / n as f64;
                let mut w = 2.0 * self.band(a) * Self::near(a) * (0.3 + 0.7 * k);
                let mut alpha = 0.9 * k.powf(1.6) * if front { 1.0 } else { 0.7 };
                if glow {
                    w *= 2.4;
                    alpha *= 0.12;
                }
                cr.set_line_width(w);
                let c = mix_rgb(self.acc, (1.0, 1.0, 1.0), 0.25 + 0.5 * k);
                cr.set_source_rgba(c.0, c.1, c.2, alpha);
                let (sx, sy) = self.spot(a, 1.0);
                cr.move_to(sx, sy);
                let (ex, ey) = self.spot(b, 1.0);
                cr.line_to(ex, ey);
                let _ = cr.stroke();
            }
        }
    }

    fn lit(&self, cr: &Context, d: &str, x: f64, y: f64, r: f64, strength: f64) {
        if strength > 0.0 {
            fill(cr, d, &radial(x, y, r, &[(0.0, self.light, 0.85 * strength), (0.45, self.light, 0.3 * strength), (1.0, self.light, 0.0)]));
        }
    }

    fn edges(&self, cr: &Context, d: &str, x: f64, y: f64, r: f64, strength: f64) {
        if strength > 0.0 {
            let _ = cr.save();
            trace(cr, d);
            cr.set_line_width(0.14);
            cr.set_line_join(cairo::LineJoin::Round);
            let _ = cr.set_source(radial(x, y, r, &[(0.0, self.hot, strength), (0.5, self.light, 0.45 * strength), (1.0, self.light, 0.0)]));
            let _ = cr.stroke();
            let _ = cr.restore();
        }
    }

    fn sector(&self, cr: &Context, t0: f64, t1: f64) {
        cr.move_to(self.o.cx, self.o.cy);
        let steps = 2.max(((t1 - t0).abs() * 24.0) as i64);
        for i in 0..=steps {
            let (x, y) = self.spot(t0 + (t1 - t0) * i as f64 / steps as f64, 3.0);
            cr.line_to(x, y);
        }
        cr.close_path();
    }

    fn draw_v(&self, cr: &Context, px: f64, py: f64, front: bool, v: &V) {
        cr.push_group();
        if v.wire > 0.0 {
            let _ = cr.save();
            trace(cr, &self.ring_v);
            cr.set_line_width(0.1);
            let c = mix_rgb(self.acc, (1.0, 1.0, 1.0), 0.35);
            cr.set_source_rgba(c.0, c.1, c.2, v.wire);
            let _ = cr.stroke();
            let _ = cr.restore();
        }
        let _ = cr.save();
        if let Some(scan) = v.scan {
            cr.rectangle(-10.0, -10.0, 50.0, scan + 10.0);
            cr.clip();
        }
        fill(cr, &self.ring_v, &self.v_fill);
        self.lit(cr, &self.ring_v, px, py, 8.0, if front { 0.32 } else { 0.12 });
        self.edges(cr, &self.ring_v, px, py, 7.0, if front { 0.9 } else { 0.35 } * v.edge);
        if v.holo > 0.0 {
            let _ = cr.save();
            trace(cr, &self.ring_v);
            cr.set_fill_rule(FillRule::EvenOdd);
            cr.clip();
            let b = rgb(&self.base);
            cr.set_source_rgba(b.0, b.1, b.2, 0.3 * v.holo);
            let mut y = 2.0;
            while y < 23.0 {
                cr.rectangle(-2.0, y, 28.0, 0.16);
                y += 0.42;
            }
            let _ = cr.fill();
            let _ = cr.restore();
        }
        if let Some(sh) = v.shimmer {
            fill(cr, &self.ring_v, &linear(0.0, sh - 1.4, 0.0, sh + 0.3,
                &[(0.0, self.light, 0.0), (0.85, mix_rgb(self.acc, (1.0, 1.0, 1.0), 0.7), 0.32), (1.0, self.light, 0.0)]));
        }
        let _ = cr.restore();
        if let Some(scan) = v.scan {
            let _ = cr.save();
            cr.rectangle(-10.0, scan - 0.5, 50.0, 0.55);
            cr.clip();
            fill(cr, &self.ring_v, &solid(self.hot, 0.9));
            let _ = cr.restore();
        }
        let _ = cr.pop_group_to_source();
        let _ = cr.paint();
        if let Some(scan) = v.scan {
            for (h, a) in [(0.9, 0.16), (0.3, 0.35), (0.07, 0.9)] {
                let _ = cr.set_source(linear(-3.0, 0.0, 27.0, 0.0, &[(0.0, self.hot, 0.0), (0.5, self.hot, a), (1.0, self.hot, 0.0)]));
                cr.rectangle(-3.0, scan - h / 2.0, 30.0, h);
                let _ = cr.fill();
            }
        }
    }

    fn frame(&self, t: Option<f64>, drawn: Option<(f64, f64)>, planet_in: f64, v: &V, flash: f64) -> ImageSurface {
        let surf = ImageSurface::create(Format::ARgb32, self.w, self.h).expect("a surface");
        {
            let cr = Context::new(&surf).expect("a context");
            cr.translate(-self.ox, -self.oy);
            cr.scale(self.k, self.k);
            let lit_up = t.is_some();
            let t = t.unwrap_or(0.0);
            let (px, py) = self.spot(t, 1.0);
            let r = self.o.pr * Self::near(t);
            let front = t.sin() > 0.0;
            let tail_len = drawn.map_or(TAIL, |d| TAIL.min(t - d.0));

            if lit_up {
                cr.push_group();
                if let Some((a, b)) = drawn {
                    let _ = cr.save();
                    self.sector(&cr, a, b);
                    cr.clip();
                }
                fill(&cr, &self.ring_back, &self.back_fill);
                self.lit(&cr, &self.ring_back, px, py, 6.0, if !front { 0.5 } else { 0.25 });
                if drawn.is_some() {
                    let _ = cr.restore();
                }
                self.tail(&cr, t, tail_len, false);
                if !front {
                    self.planet(&cr, px, py, r, 0.8 * planet_in);
                }
                cr.set_operator(Operator::DestOut);
                fill(&cr, &self.ring_hide, &solid((0.0, 0.0, 0.0), 1.0));
                let _ = cr.pop_group_to_source();
                let _ = cr.paint();
            }

            self.draw_v(&cr, px, py, front && lit_up, v);

            if lit_up {
                if let Some((a, b)) = drawn {
                    let _ = cr.save();
                    self.sector(&cr, a, b);
                    cr.clip();
                }
                fill(&cr, &self.ring_front, &self.front_fill);
                self.lit(&cr, &self.ring_front, px, py, 6.0, if front { 0.6 } else { 0.2 });
                if drawn.is_some() {
                    let _ = cr.restore();
                }
                self.tail(&cr, t, tail_len, true);
                if front {
                    self.planet(&cr, px, py, r, planet_in);
                }
            }
            if flash > 0.0 {
                let big = 1.5 + 7.0 * (1.0 - flash);
                let _ = cr.set_source(radial(px, py, big, &[(0.0, (1.0, 1.0, 1.0), flash), (0.25, self.hot, 0.6 * flash), (1.0, self.hot, 0.0)]));
                cr.arc(px, py, big, 0.0, 2.0 * PI);
                let _ = cr.fill();
            }
        }
        surf.flush();
        surf
    }

    fn angle_at(&self, time: f64) -> f64 {
        let fine = self.times.len() - 1;
        let step = 2.0 * PI / fine as f64;
        let target = (time / LOOP as f64).rem_euclid(1.0) * self.turn;
        let (mut lo, mut hi) = (0, fine);
        while hi - lo > 1 {
            let mid = (lo + hi) / 2;
            if self.times[mid] <= target { lo = mid } else { hi = mid }
        }
        let frac = (target - self.times[lo]) / (self.times[hi] - self.times[lo]);
        (lo as f64 + frac) * step + (time / LOOP as f64).floor() * 2.0 * PI
    }
}

#[derive(Default)]
struct V {
    scan: Option<f64>,
    wire: f64,
    holo: f64,
    shimmer: Option<f64>,
    edge: f64,
}

fn mix_rgb(a: Rgb, b: Rgb, t: f64) -> Rgb {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
}

fn glitch(surf: &ImageSurface, rnd: &mut pyrandom::Random) -> ImageSurface {
    let (w, h, stride) = (surf.width() as usize, surf.height() as usize, surf.stride() as usize);
    let mut src = ImageSurface::create(Format::ARgb32, w as i32, h as i32).expect("a surface");
    {
        let c = Context::new(&src).expect("a context");
        let _ = c.set_source_surface(surf, 0.0, 0.0);
        let _ = c.paint();
    }
    src.flush();
    let data: Vec<u8> = src.data().expect("its pixels").to_vec();
    let mut shift = vec![0i64; h];
    for _ in 0..rnd.randint(2, 4) {
        let y0 = rnd.randrange(h as u32) as usize;
        let hh = rnd.randint(2, 9) as usize;
        let dx = rnd.choice(&[-1i64, 1]) * rnd.randint(3, 10);
        for s in shift.iter_mut().take(h.min(y0 + hh)).skip(y0) {
            *s = dx;
        }
    }
    let split = rnd.randint(2, 4);
    let mut out = ImageSurface::create(Format::ARgb32, w as i32, h as i32).expect("a surface");
    {
        let ostride = out.stride() as usize;
        let mut dst = out.data().expect("its pixels");
        for (y, &dy) in shift.iter().enumerate() {
            let row = y * stride;
            let px = |xx: i64, c: usize| -> u8 {
                let xx = xx - dy;
                if xx >= 0 && (xx as usize) < w { data[row + xx as usize * 4 + c] } else { 0 }
            };
            for x in 0..w as i64 {
                let (b, g, r) = (px(x + split, 0), px(x, 1), px(x - split, 2));
                let a = px(x + split, 3).max(px(x, 3)).max(px(x - split, 3));
                let o = y * ostride + x as usize * 4;
                dst[o] = b.min(a);
                dst[o + 1] = g.min(a);
                dst[o + 2] = r.min(a);
                dst[o + 3] = a;
            }
        }
    }
    out.mark_dirty();
    out
}

fn write_png(surf: &ImageSurface, path: &Path) {
    let mut f = fs::File::create(path).expect("a picture");
    surf.write_to_png(&mut f).expect("written");
}

fn deeper(hex: &str) -> String {
    let h = hex.trim_start_matches('#');
    let c = |i: usize| (u8::from_str_radix(&h[i..i + 2], 16).unwrap_or(0) as f64 * 0.72).round() as u8;
    format!("#{:02x}{:02x}{:02x}", c(0), c(2), c(4))
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("--version") {
        println!("{SPLASH_VERSION}");
        return;
    }
    let (Some(out), Some(flavor), Some(accent_name)) = (args.first(), args.get(1), args.get(2)) else {
        eprintln!("splash-render OUT FLAVOR ACCENT [SIZE]");
        std::process::exit(2);
    };
    let l: f64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(176.0);
    let k = l / 24.0;
    let out = PathBuf::from(out);
    let shape = shape();
    let pal = palette(flavor);
    let (base, text) = (pal["base"].clone(), pal["text"].clone());
    let (acc_hex, _) = accent(pal, accent_name);
    let partner = deeper(&acc_hex);
    let acc = rgb(&acc_hex);
    let num = |v: &Value| v.as_f64().unwrap_or(0.0);
    let ob = &shape["orbit"];
    let o = Orbit {
        cx: num(&ob["cx"]), cy: num(&ob["cy"]), rx: num(&ob["rx"]), ry: num(&ob["ry"]),
        tilt: num(&ob["tilt"]).to_radians(), pr: num(&ob["planet"]["r"]),
        width: (num(&ob["width"][0]), num(&ob["width"][1])), planet: (num(&ob["planet"]["x"]), num(&ob["planet"]["y"])),
    };
    let light = mix(&acc_hex, WHITE, 0.55);
    let hot = mix(&acc_hex, WHITE, 0.8);
    let (x0, plx) = (o.cx - o.rx, o.planet.0);
    let ring = |n: &str| shape["ring"][n].as_str().unwrap_or("").to_string();

    let fine = 20000;
    let step = 2.0 * PI / fine as f64;
    let mut times = vec![0.0];
    let mut a = 0.0;
    for i in 0..fine {
        a += step / (1.0 + ECC * (i as f64 * step + step / 2.0).sin());
        times.push(a);
    }

    let mut s = Splash {
        k, acc, light, hot, base: base.clone(),
        v_fill: linear(2.0, 3.0, 20.0, 21.0, &[(0.0, mix(&acc_hex, WHITE, 0.2), 1.0), (1.0, rgb(&partner), 1.0)]),
        front_fill: linear(x0, 0.0, plx, 0.0, &[(0.0, mix(&partner, &base, 0.2), 1.0), (0.55, acc, 1.0), (1.0, mix(&acc_hex, WHITE, 0.5), 1.0)]),
        back_fill: linear(x0, 0.0, plx, 0.0, &[(0.0, mix(&partner, &base, 0.2), 1.0), (1.0, mix(&acc_hex, &base, 0.5), 1.0)]),
        ring_v: ring("v"), ring_back: ring("back"), ring_front: ring("front"), ring_hide: ring("hide"),
        o, ox: 0.0, oy: 0.0, w: 0, h: 0, times, turn: a,
    };

    let pad = s.o.pr * 1.18 * 2.6 + 0.4;
    let pts: Vec<(f64, f64)> = (0..180).map(|i| s.spot(i as f64 * PI / 90.0, 1.0)).collect();
    let (minx, maxx) = pts.iter().fold((f64::MAX, f64::MIN), |(lo, hi), p| (lo.min(p.0), hi.max(p.0)));
    let (miny, maxy) = pts.iter().fold((f64::MAX, f64::MIN), |(lo, hi), p| (lo.min(p.1), hi.max(p.1)));
    s.ox = ((minx - pad).min(-3.0) * k).floor();
    s.oy = ((miny - pad).min(2.4) * k).floor();
    s.w = ((maxx + pad).max(27.0) * k).ceil() as i32 - s.ox as i32;
    s.h = ((maxy + pad).max(22.6) * k).ceil() as i32 - s.oy as i32;

    fs::create_dir_all(&out).expect("the theme's folder");
    let mut loop_px: Vec<(f64, f64, u8)> = Vec::new();
    let mut intro_px: Vec<(f64, f64, u8)> = Vec::new();
    let keep = |s: &Splash, list: &mut Vec<(f64, f64, u8)>, t: f64| {
        let (x, y) = s.spot(t, 1.0);
        list.push((round1(x * k), round1(y * k), if t.sin() > 0.0 { 1 } else { 0 }));
    };

    for i in 0..LOOP {
        let t = s.angle_at(i as f64);
        let sweep = i as f64 / (LOOP as f64 * 0.5);
        let v = V { shimmer: (sweep <= 1.0).then_some(1.0 + 23.0 * sweep), edge: 1.0, ..Default::default() };
        write_png(&s.frame(Some(t), None, 1.0, &v, 0.0), &out.join(format!("loop-{i}.png")));
        keep(&s, &mut loop_px, t);
    }

    let span = (INTRO - IGNITE) as f64;
    let boost = (LOOP as f64 - span) / (15.0 * (1.0 - (-span / 15.0).exp()));
    let intro_clock = |f: f64| {
        let s = f - IGNITE as f64;
        s + boost * 15.0 * (1.0 - (-s / 15.0).exp())
    };
    let mut rnd = pyrandom::Random::new(7);
    let glitches = [18, 19, 31, 44, 45];
    for f in 0..INTRO {
        let ff = f as f64;
        let scan = (f < 48).then(|| 2.4 + 19.4 * ease((ff - 6.0) / 40.0));
        let mut v = V {
            scan: if f >= 6 { scan } else { Some(2.0) },
            wire: (ff / 8.0).min(1.0) * if scan.is_some() || f < 6 { 0.9 } else { (1.0 - (ff - 48.0) / 10.0).max(0.0) },
            holo: (1.0 - (ff - 48.0).max(0.0) / 40.0).max(0.0),
            edge: ((ff - IGNITE as f64) / 20.0).clamp(0.0, 1.0),
            shimmer: None,
        };
        if f >= 100 {
            v.shimmer = Some(1.0 + 23.0 * (ff - 100.0) / 26.0);
        }
        let mut surf = if f < IGNITE {
            intro_px.push((round1(s.o.planet.0 * k), round1(s.o.planet.1 * k), 0));
            s.frame(None, None, 1.0, &v, 0.0)
        } else {
            let t = s.angle_at(intro_clock(ff));
            keep(&s, &mut intro_px, t);
            s.frame(Some(t), Some((-0.02, t + 0.02)), ease((ff - IGNITE as f64) / 4.0), &v, (1.0 - (ff - IGNITE as f64) / 14.0).max(0.0).powi(2))
        };
        if glitches.contains(&f) {
            surf = glitch(&surf, &mut rnd);
        }
        write_png(&surf, &out.join(format!("intro-{f}.png")));
    }

    let name: Vec<char> = "VYNTARIS".chars().collect();
    let glyphs: Vec<char> = "0123456789ABCDEF<>/\\|=+*#".chars().collect();
    let font_px = (l * 0.095).round_ties_even();
    let gap = font_px * 0.95;
    let (ww, wh) = ((gap * (name.len() - 1) as f64 + font_px * 2.0) as i32, (font_px * 1.8) as i32);
    let text_rgb = rgb(&text);
    for f in 0..WORD {
        let surf = ImageSurface::create(Format::ARgb32, ww, wh).expect("a surface");
        {
            let cr = Context::new(&surf).expect("a context");
            cr.select_font_face("Inter", cairo::FontSlant::Normal, cairo::FontWeight::Normal);
            cr.set_font_size(font_px);
            for (i, ch) in name.iter().enumerate() {
                let (start, lock) = (i * 4, 18 + i * 6);
                if f < start {
                    continue;
                }
                let settled = f >= lock;
                let glyph = if settled { *ch } else { pyrandom::Random::new((f / 2 * 31 + i) as u64).choice(&glyphs) };
                let g = glyph.to_string();
                let ext = cr.text_extents(&g).expect("its extents");
                let x = font_px / 2.0 + i as f64 * gap + (font_px * 0.7 - ext.x_advance()) / 2.0;
                if settled {
                    let heat = (1.0 - (f - lock) as f64 / 8.0).max(0.0);
                    let c = mix_rgb(text_rgb, s.hot, heat);
                    cr.set_source_rgba(c.0, c.1, c.2, 0.85);
                } else {
                    cr.set_source_rgba(acc.0, acc.1, acc.2, 0.55);
                }
                cr.move_to(x, wh as f64 * 0.68);
                let _ = cr.show_text(&g);
            }
        }
        write_png(&surf, &out.join(format!("word-{f}.png")));
    }

    let sprite = |name: &str, w: i32, h: i32, paint: &dyn Fn(&Context)| {
        let surf = ImageSurface::create(Format::ARgb32, w, h).expect("a surface");
        {
            let cr = Context::new(&surf).expect("a context");
            paint(&cr);
        }
        write_png(&surf, &out.join(format!("{name}.png")));
    };

    let r = (l * 1.5) as i32;
    let rr = r as f64;
    sprite("halo", 2 * r, 2 * r, &|cr| {
        let _ = cr.set_source(radial(rr, rr, rr, &[(0.0, acc, 0.16), (0.35, acc, 0.07), (0.7, acc, 0.015), (1.0, acc, 0.0)]));
        let _ = cr.paint();
    });

    let (fw, fh) = ((l * 2.2) as i32, 24);
    sprite("flare", fw, fh, &|cr| {
        for (h, a) in [(fh as f64, 0.12), (8.0, 0.3), (2.4, 0.85)] {
            let _ = cr.save();
            cr.translate(fw as f64 / 2.0, fh as f64 / 2.0);
            cr.scale(fw as f64 / 2.0, h / 2.0);
            let _ = cr.set_source(radial(0.0, 0.0, 1.0, &[(0.0, s.hot, a), (0.25, s.light, a * 0.35), (1.0, s.light, 0.0)]));
            cr.arc(0.0, 0.0, 1.0, 0.0, 2.0 * PI);
            let _ = cr.fill();
            let _ = cr.restore();
        }
    });

    let dot = mix(&acc_hex, WHITE, 0.3);
    for n in 1..4 {
        let d = n * 2 + 2;
        let df = d as f64;
        sprite(&format!("dot-{n}"), d, d, &|cr| {
            let _ = cr.set_source(radial(df / 2.0, df / 2.0, df / 2.0, &[(0.0, s.hot, 1.0), (0.45, dot, 0.85), (1.0, dot, 0.0)]));
            let _ = cr.paint();
        });
    }

    let px_json = |l: &[(f64, f64, u8)]| Value::Array(l.iter().map(|(x, y, f)| json!([x, y, f])).collect());
    let paths = json!([
        {"scale": 1.75, "dots": 56, "dashes": 4, "duty": 0.62, "spin": 0.0042, "alpha": 0.42},
        {"scale": 2.5, "dots": 84, "dashes": 12, "duty": 0.5, "spin": -0.0026, "alpha": 0.26},
    ]);
    let scene = json!({
        "size": l as i64, "x": s.ox as i64, "y": s.oy as i64, "width": s.w, "height": s.h, "fps": FPS, "loop": LOOP, "intro": INTRO,
        "ignite": IGNITE, "word": WORD, "wordWidth": ww, "wordHeight": wh, "halo": 2 * r, "flare": [fw, fh],
        "orbit": {"cx": ob["cx"], "cy": ob["cy"], "rx": ob["rx"], "ry": ob["ry"], "tilt": ob["tilt"]},
        "paths": paths, "pulseDots": 48, "pulseFrames": 70,
        "planet": {"loop": px_json(&loop_px), "intro": px_json(&intro_px)},
        "flavor": flavor, "accent": accent_name, "base": base, "crust": pal["crust"], "text": text,
    });
    fs::write(out.join("frames.json"), serde_json::to_string_pretty(&scene).expect("json")).expect("frames.json");
    fs::write(out.join("version"), format!("{SPLASH_VERSION}\n")).expect("version");

    let rgbs = |h: &str| { let c = rgb(h); format!("{:.3}, {:.3}, {:.3}", c.0, c.1, c.2) };
    let mut planet_lines = Vec::new();
    for (kind, list) in [("loop", &loop_px), ("intro", &intro_px)] {
        for (i, (x, y, f)) in list.iter().enumerate() {
            planet_lines.push(format!("{kind}_px[{i}] = {}; {kind}_py[{i}] = {}; {kind}_pf[{i}] = {f};", py(*x), py(*y)));
        }
    }
    let path_lines: Vec<String> = paths.as_array().expect("paths").iter().enumerate().map(|(i, p)| format!(
        "path[{i}].scale = {}; path[{i}].dots = {}; path[{i}].dashes = {}; path[{i}].duty = {}; path[{i}].spin = {}; path[{i}].alpha = {};",
        py(num(&p["scale"])), p["dots"], p["dashes"], py(num(&p["duty"])), py(num(&p["spin"])), py(num(&p["alpha"])))).collect();
    let subs = |key: &str| -> String {
        match key {
            "L" => (l as i64).to_string(), "LOOP" => LOOP.to_string(), "INTRO" => INTRO.to_string(), "IGNITE" => IGNITE.to_string(),
            "WORD" => WORD.to_string(), "FX" => (s.ox as i64).to_string(), "FY" => (s.oy as i64).to_string(), "HALO" => (2 * r).to_string(),
            "FLAREW" => fw.to_string(), "FLAREH" => fh.to_string(), "WORDW" => ww.to_string(), "WORDH" => wh.to_string(),
            "CX" => py(s.o.cx * k), "CY" => py(s.o.cy * k), "RX" => py(s.o.rx * k), "RY" => py(s.o.ry * k), "TILT" => py(s.o.tilt),
            "PULSEDOTS" => "48".into(), "PULSEFRAMES" => "70".into(), "PATHS" => "2".into(),
            "BASE" => rgbs(&base), "CRUST" => rgbs(&pal["crust"]), "TEXT" => rgbs(&text),
            "PLANET" => planet_lines.join("\n"), "PATHLIST" => path_lines.join("\n"),
            other => format!("@{other}@"),
        }
    };
    let script = Regex::new(r"@([A-Z]+)@").unwrap().replace_all(SCRIPT_IN, |c: &regex::Captures| subs(&c[1])).into_owned();
    fs::write(out.join("island.script"), script).expect("island.script");
    println!("{} frames of {} x {} in {}", INTRO + LOOP, s.w, s.h, out.display());
}
