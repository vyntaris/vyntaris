use regex::bytes::Regex as BytesRegex;
use regex::Regex;
use rusqlite::{Connection, OpenFlags, params};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::os::fd::AsRawFd;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::LazyLock;

const LONGEST: usize = 200_000;
const BIGGEST: u64 = 64 * 1024 * 1024;
const SKIP: &[&str] = &["node_modules", "target", "__pycache__", "venv", ".venv"];
const TEXT: &[&str] = &[".txt", ".md", ".markdown", ".csv", ".tsv", ".rst", ".org", ".tex", ".log", ".json", ".xml", ".html", ".htm", ".rtf"];

fn zipped(ext: &str) -> Option<&'static [&'static str]> {
    Some(match ext {
        ".docx" => &["word/document.xml", "word/header*.xml", "word/footer*.xml"],
        ".xlsx" => &["xl/sharedStrings.xml", "xl/worksheets/sheet*.xml"],
        ".pptx" => &["ppt/slides/slide*.xml"],
        ".odt" | ".ods" | ".odp" => &["content.xml"],
        ".vdoc" => &["word/document.xml", "content.xml"],
        ".vsheet" => &["xl/sharedStrings.xml", "content.xml"],
        _ => return None,
    })
}

fn db_path() -> PathBuf {
    vyntaris_core::paths::cache_home().join("vyntaris").join("documents.db")
}

fn ext_of(path: &Path) -> String {
    path.extension().map(|e| format!(".{}", e.to_string_lossy().to_lowercase())).unwrap_or_default()
}

fn user_dir(name: &str, fallback: &str) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_default();
    let d = Command::new("xdg-user-dir").arg(name).output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string()).unwrap_or_default();
    if !d.is_empty() && d != home { PathBuf::from(d) } else { PathBuf::from(fallback.replacen('~', &home, 1)) }
}

fn roots() -> Vec<PathBuf> {
    let mut r: Vec<PathBuf> = vec![user_dir("DOCUMENTS", "~/Documents"), user_dir("DESKTOP", "~/Desktop"), user_dir("DOWNLOAD", "~/Downloads")];
    r.sort();
    r.dedup();
    r
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut entries: Vec<_> = entries.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for e in entries {
        let name = e.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        let Ok(kind) = e.file_type() else { continue };
        if kind.is_dir() {
            if !SKIP.contains(&name.as_str()) {
                walk(&e.path(), out);
            }
        } else {
            let ext = ext_of(&e.path());
            if TEXT.contains(&ext.as_str()) || zipped(&ext).is_some() || ext == ".pdf" {
                out.push(e.path());
            }
        }
    }
}

fn files() -> Vec<PathBuf> {
    let mut out = Vec::new();
    for root in roots() {
        walk(&root, &mut out);
    }
    out
}

fn unescape(s: &str) -> String {
    static ENTITY: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);").unwrap());
    ENTITY.replace_all(s, |c: &regex::Captures| {
        let e = &c[1];
        let ch = if let Some(hex) = e.strip_prefix("#x").or_else(|| e.strip_prefix("#X")) {
            u32::from_str_radix(hex, 16).ok().and_then(char::from_u32)
        } else if let Some(dec) = e.strip_prefix('#') {
            dec.parse().ok().and_then(char::from_u32)
        } else {
            match e { "amp" => Some('&'), "lt" => Some('<'), "gt" => Some('>'), "quot" => Some('"'), "apos" => Some('\''), "nbsp" => Some('\u{a0}'), _ => None }
        };
        ch.map_or_else(|| c[0].to_string(), |ch| ch.to_string())
    }).into_owned()
}

fn strip_tags(s: &str, with: &str) -> String {
    static TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<[^>]+>").unwrap());
    TAG.replace_all(s, with).into_owned()
}

fn xml_text(data: &[u8]) -> String {
    static ENDS: LazyLock<BytesRegex> = LazyLock::new(|| BytesRegex::new(r"</(w:p|a:p|text:p|text:h|c|si|row|table:table-cell)>").unwrap());
    let data = ENDS.replace_all(data, &b" \n"[..]);
    unescape(&strip_tags(&String::from_utf8_lossy(&data), ""))
}

fn glob(pattern: &str, name: &str) -> bool {
    let Some((head, tail)) = pattern.split_once('*') else { return pattern == name };
    name.len() >= head.len() + tail.len() && name.starts_with(head) && name.ends_with(tail)
}

fn read_zip(path: &Path) -> Result<zip::ZipArchive<fs::File>, String> {
    zip::ZipArchive::new(fs::File::open(path).map_err(|e| e.to_string())?).map_err(|e| e.to_string())
}

fn part(z: &mut zip::ZipArchive<fs::File>, name: &str) -> Result<Vec<u8>, String> {
    let mut f = z.by_name(name).map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    f.read_to_end(&mut out).map_err(|e| e.to_string())?;
    Ok(out)
}

fn extract(path: &Path) -> Result<String, String> {
    let ext = ext_of(path);
    if ext == ".pdf" {
        let out = Command::new("pdftotext").args(["-l", "60", "-q"]).arg(path).arg("-").output().map_err(|e| e.to_string())?;
        return Ok(String::from_utf8_lossy(&out.stdout).into_owned());
    }
    if let Some(patterns) = zipped(&ext) {
        let mut z = read_zip(path)?;
        let names: Vec<String> = z.file_names().filter_map(|n| n.ok().map(|n| n.into_owned())).collect();
        let mut parts = Vec::new();
        for pattern in patterns {
            let mut hits: Vec<&String> = names.iter().filter(|n| glob(pattern, n)).collect();
            hits.sort();
            for n in hits {
                parts.push(xml_text(&part(&mut z, n)?));
            }
        }
        return Ok(parts.join("\n"));
    }
    let mut raw = Vec::new();
    fs::File::open(path).map_err(|e| e.to_string())?.take((LONGEST * 2) as u64).read_to_end(&mut raw).map_err(|e| e.to_string())?;
    let raw = String::from_utf8_lossy(&raw).into_owned();
    Ok(match ext.as_str() {
        ".html" | ".htm" | ".xml" => unescape(&strip_tags(&raw, " ")),
        ".rtf" => {
            static RTF: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\\[a-z]+-?\d* ?|[{}]").unwrap());
            RTF.replace_all(&raw, "").into_owned()
        }
        _ => raw,
    })
}

fn column(letters: &str) -> usize {
    letters.bytes().fold(0usize, |n, c| n * 26 + (c - b'A' + 1) as usize).saturating_sub(1)
}

fn table(path: &Path, rows: usize, cols: usize) -> Result<Vec<Vec<String>>, String> {
    let ext = ext_of(path);
    let mut out: Vec<Vec<String>> = Vec::new();
    if ext == ".csv" || ext == ".tsv" {
        let mut r = csv::ReaderBuilder::new().has_headers(false).flexible(true).delimiter(if ext == ".tsv" { b'\t' } else { b',' })
            .from_path(path).map_err(|e| e.to_string())?;
        for rec in r.records().flatten() {
            out.push(rec.iter().take(cols).map(str::to_string).collect());
            if out.len() >= rows {
                break;
            }
        }
        return Ok(out);
    }
    let mut z = read_zip(path)?;
    let names: Vec<String> = z.file_names().filter_map(|n| n.ok().map(|n| n.into_owned())).collect();
    if ext == ".xlsx" || ext == ".vsheet" {
        static SI: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<si>(.*?)</si>").unwrap());
        static T: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<t[^>]*>(.*?)</t>").unwrap());
        static SHEET: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^xl/worksheets/sheet\d+\.xml$").unwrap());
        static ROW: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<row[^>]*>(.*?)</row>").unwrap());
        static CELL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<c ([^>]*?)(?:/>|>(.*?)</c>)").unwrap());
        static REF: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"r="([A-Z]+)\d+""#).unwrap());
        static V: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<v>(.*?)</v>").unwrap());
        static KIND: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"t="(\w+)""#).unwrap());
        let mut strings = Vec::new();
        if names.iter().any(|n| n == "xl/sharedStrings.xml") {
            let data = String::from_utf8_lossy(&part(&mut z, "xl/sharedStrings.xml")?).into_owned();
            for si in SI.captures_iter(&data) {
                strings.push(unescape(&T.captures_iter(&si[1]).map(|t| t[1].to_string()).collect::<String>()));
            }
        }
        let mut sheets: Vec<&String> = names.iter().filter(|n| SHEET.is_match(n)).collect();
        sheets.sort();
        let Some(first) = sheets.first() else { return Ok(out) };
        let data = String::from_utf8_lossy(&part(&mut z, first)?).into_owned();
        for row in ROW.captures_iter(&data).take(rows) {
            let mut cells: Vec<String> = Vec::new();
            for c in CELL.captures_iter(&row[1]) {
                let (attrs, body) = (&c[1], c.get(2).map_or("", |m| m.as_str()));
                let i = REF.captures(attrs).map_or(cells.len(), |r| column(&r[1]));
                if i >= cols {
                    continue;
                }
                let v = V.captures(body).map(|v| v[1].to_string());
                let kind = KIND.captures(attrs).map(|k| k[1].to_string());
                let text = match (kind.as_deref(), &v) {
                    (Some("s"), Some(v)) => v.parse::<usize>().ok().and_then(|n| strings.get(n).cloned()).unwrap_or_default(),
                    (Some("inlineStr"), _) => T.captures_iter(body).map(|t| t[1].to_string()).collect(),
                    _ => v.unwrap_or_default(),
                };
                if cells.len() < i + 1 {
                    cells.resize(i + 1, String::new());
                }
                cells[i] = unescape(&text);
            }
            out.push(cells);
        }
    } else {
        static TABLE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<table:table [^>]*>(.*?)</table:table>").unwrap());
        static ROW: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<table:table-row[^>]*>(.*?)</table:table-row>").unwrap());
        static CELL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?s)<table:table-cell([^>]*?)(?:/>|>(.*?)</table:table-cell>)").unwrap());
        static REP: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"number-columns-repeated="(\d+)""#).unwrap());
        let data = String::from_utf8_lossy(&part(&mut z, "content.xml")?).into_owned();
        let sheet = TABLE.captures(&data).map(|s| s[1].to_string()).unwrap_or_default();
        for row in ROW.captures_iter(&sheet).take(rows) {
            let mut cells: Vec<String> = Vec::new();
            for c in CELL.captures_iter(&row[1]) {
                let rep = REP.captures(&c[1]).and_then(|r| r[1].parse::<usize>().ok()).unwrap_or(1);
                let text = unescape(&strip_tags(c.get(2).map_or("", |m| m.as_str()), ""));
                let n = rep.min(cols.saturating_sub(cells.len()));
                cells.extend(std::iter::repeat_n(text, n));
                if cells.len() >= cols {
                    break;
                }
            }
            while cells.last().is_some_and(String::is_empty) {
                cells.pop();
            }
            out.push(cells);
        }
    }
    while out.last().is_some_and(|r| r.iter().all(String::is_empty)) {
        out.pop();
    }
    Ok(out)
}

fn connect() -> rusqlite::Result<Connection> {
    let db = Connection::open(db_path())?;
    db.execute_batch(
        "CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, mtime REAL, size INTEGER);
         CREATE VIRTUAL TABLE IF NOT EXISTS text USING fts5(path UNINDEXED, name, body,
             tokenize = 'unicode61 remove_diacritics 2');
         CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);",
    )?;
    Ok(db)
}

fn mtime(m: &fs::Metadata) -> f64 {
    m.mtime() as f64 + m.mtime_nsec() as f64 / 1e9
}

fn index() -> rusqlite::Result<()> {
    let path = db_path();
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let Ok(lock) = fs::File::create(path.with_extension("db.lock")) else { return Ok(()) };
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
        return Ok(());
    }
    let mut db = connect()?;
    let known: HashMap<String, (f64, i64)> = db
        .prepare("SELECT path, mtime, size FROM files")?
        .query_map([], |r| Ok((r.get::<_, String>(0)?, (r.get::<_, f64>(1)?, r.get::<_, i64>(2)?))))?
        .flatten()
        .collect();
    let mut seen = HashSet::new();
    let mut added = 0;
    for file in files() {
        let p = file.to_string_lossy().to_string();
        seen.insert(p.clone());
        let Ok(meta) = fs::metadata(&file) else { continue };
        if known.get(&p) == Some(&(mtime(&meta), meta.size() as i64)) || meta.size() > BIGGEST {
            continue;
        }
        let body: String = extract(&file).unwrap_or_default().chars().take(LONGEST).collect();
        let name = file.file_name().map(|f| f.to_string_lossy().to_string()).unwrap_or_default();
        let tx = db.transaction()?;
        tx.execute("DELETE FROM text WHERE path = ?1", params![p])?;
        tx.execute("INSERT INTO text (path, name, body) VALUES (?1, ?2, ?3)", params![p, name, body])?;
        tx.execute("INSERT OR REPLACE INTO files VALUES (?1, ?2, ?3)", params![p, mtime(&meta), meta.size() as i64])?;
        tx.commit()?;
        added += 1;
    }
    let gone: Vec<&String> = known.keys().filter(|p| !seen.contains(*p)).collect();
    let tx = db.transaction()?;
    for p in &gone {
        tx.execute("DELETE FROM text WHERE path = ?1", params![p])?;
        tx.execute("DELETE FROM files WHERE path = ?1", params![p])?;
    }
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    tx.execute("INSERT OR REPLACE INTO meta VALUES ('indexed', ?1)", params![now.to_string()])?;
    tx.commit()?;
    println!("{added} documents read, {} gone, {} in all", gone.len(), seen.len());
    Ok(())
}

fn read_only() -> Option<Connection> {
    let path = db_path();
    path.exists().then(|| Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).ok()).flatten()
}

fn search(words: &str, limit: i64) {
    let Some(db) = read_only() else { return };
    static WORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\w+").unwrap());
    let tokens: Vec<&str> = WORD.find_iter(words).map(|m| m.as_str()).collect();
    let Some((last, rest)) = tokens.split_last() else { return };
    let mut query: Vec<String> = rest.iter().map(|t| format!("\"{t}\"")).collect();
    query.push(format!("\"{last}\"*"));
    let Ok(mut st) = db.prepare("SELECT path, snippet(text, 2, '', '', '…', 8) FROM text WHERE text MATCH ?1 ORDER BY bm25(text, 0, 4, 1) LIMIT ?2") else { return };
    let Ok(rows) = st.query_map(params![query.join(" "), limit], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?))) else { return };
    for (path, snip) in rows.flatten() {
        if Path::new(&path).exists() {
            println!("{path}\t{}", snip.unwrap_or_default().split_whitespace().collect::<Vec<_>>().join(" "));
        }
    }
}

fn stats() {
    let Some(db) = read_only() else {
        println!("no index yet");
        return;
    };
    let n: i64 = db.query_row("SELECT count(*) FROM files", [], |r| r.get(0)).unwrap_or(0);
    let when: i64 = db.query_row("SELECT value FROM meta WHERE key = 'indexed'", [], |r| r.get::<_, String>(0)).ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    println!("{n} documents, brought up to date {}", local_time(when));
}

fn local_time(t: i64) -> String {
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&(t as libc::time_t), &mut tm) };
    format!("{:04}-{:02}-{:02} {:02}:{:02}", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min)
}

fn main() {
    let a: Vec<String> = std::env::args().skip(1).collect();
    let a: Vec<&str> = a.iter().map(String::as_str).collect();
    match a.as_slice() {
        ["index"] => {
            if let Err(e) = index() {
                eprintln!("the index: {e}");
                std::process::exit(1);
            }
        }
        ["search", words, rest @ ..] => search(words, rest.first().and_then(|l| l.parse().ok()).unwrap_or(8)),
        ["stats"] => stats(),
        ["table", file] => match table(Path::new(file), 200, 30) {
            Ok(rows) => {
                for r in rows {
                    println!("{}", r.iter().map(|c| c.replace(['\t', '\n'], " ")).collect::<Vec<_>>().join("\t"));
                }
            }
            Err(e) => {
                eprintln!("can't read {file}: {e}");
                std::process::exit(1);
            }
        },
        ["text", file] => match extract(Path::new(file)) {
            Ok(t) => print!("{}", t.chars().take(LONGEST).collect::<String>()),
            Err(e) => {
                eprintln!("can't read {file}: {e}");
                std::process::exit(1);
            }
        },
        _ => {
            eprintln!("doc-index index | search WORDS [LIMIT] | stats | text FILE | table FILE");
            std::process::exit(2);
        }
    }
}
