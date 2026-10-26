use vyntaris_core::palette::{accent, is_hex, palette};

fn main() {
    let colours: Vec<String> = std::env::args().skip(1).collect();
    for flavour in ["mocha", "latte"] {
        for c in &colours {
            let (a, partner) = accent(palette(flavour), c);
            println!("{flavour} {c} {a} {}", if is_hex(c) { partner.as_str() } else { "-" });
        }
    }
}
