mod checks;
mod fixes;
mod report;
mod sys;

use serde_json::{Value, json};
use std::io::Read;
use sys::{Real, Sys};

fn findings(sys: &dyn Sys) -> Vec<Value> {
    let mut all: Vec<Value> = checks::CHECKS.iter().flat_map(|c| c(sys)).collect();
    all.sort_by_key(|f| {
        checks::LEVELS
            .iter()
            .position(|l| Some(*l) == f["level"].as_str())
            .unwrap_or(9)
    });
    all
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL) };
    let root = unsafe { libc::geteuid() } == 0;
    match a.as_slice() {
        ["--report"] => {
            vyntaris_core::i18n::english();
            let text = std::env::var("VYNTARIS_REPORT").unwrap_or_else(|_| {
                let mut s = String::new();
                if unsafe { libc::isatty(0) } == 0 {
                    let _ = std::io::stdin().read_to_string(&mut s);
                }
                s
            });
            let f = findings(&Real);
            println!(
                "{}",
                report::report(&text, &Real.private_words(), report::sections(&Real, &f))
            );
        }
        ["--fix", ids @ ..] if !ids.is_empty() => {
            std::process::exit(if fixes::fix(&Real, ids, root) { 0 } else { 1 })
        }
        [] => {
            if root {
                eprintln!("the checks run as the user; root only fixes (--fix)");
                std::process::exit(2);
            }
            println!(
                "{}",
                json!({ "checked": Real.now() as u64, "findings": findings(&Real) })
            );
        }
        _ => {
            eprintln!("doctor | doctor --report | doctor --fix ID…");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests;
