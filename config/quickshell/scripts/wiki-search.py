#!/usr/bin/env python3
"""A search engine for the Arch Wiki's offline pages: every section of every page in SQLite's FTS5.

wiki-search.py build LANG    makes or refreshes LANG's index
wiki-search.py search LANG QUERY    prints the best pages as JSON
"""
import difflib
import glob
import html
import json
import os
import re
import sqlite3
import sys

ROOT = os.environ.get("ARCH_WIKI_ROOT", "/usr/share/doc/arch-wiki/html")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "vyntaris", "wiki-index")
VERSION = 2
LIMIT = 20
OPEN, CLOSE = "\x02", "\x03"

HEADING = re.compile(r'<h([2-6])\b[^>]*\bid="([^"]*)"[^>]*>(.*?)</h\1>', re.S)
TAG = re.compile(r"<[^>]+>")
NOISE = re.compile(r"<(style|script)\b.*?</\1>", re.S)
TITLE = re.compile(r"<title>([^<]*)</title>")
SPACE = re.compile(r"\s+")
WORD = re.compile(r"[^\W_]+", re.U)

COMMON = {"a", "an", "and", "are", "broken", "can", "do", "does", "doesn", "error", "fix", "for", "how", "i", "in", "is", "issue", "it", "my", "no", "not", "of", "on", "or", "problem", "t", "the", "to", "with", "work", "working", "works"}
SAME = {"wifi": ["wifi", "wireless"], "wireless": ["wifi", "wireless"], "sound": ["sound", "audio"], "audio": ["sound", "audio"]}


def index_path(lang):
    return os.path.join(CACHE, lang + ".db")


def stamp(lang):
    return f"{VERSION} {os.stat(os.path.join(ROOT, lang)).st_mtime_ns}"


def clean(text):
    return SPACE.sub(" ", html.unescape(TAG.sub(" ", text))).strip()


def build(lang):
    target = index_path(lang)
    try:
        with sqlite3.connect(f"file:{target}?mode=ro", uri=True) as old:
            if old.execute("select value from meta where key = 'stamp'").fetchone()[0] == stamp(lang):
                return
    except sqlite3.Error:
        pass
    os.makedirs(CACHE, exist_ok=True)
    temporary = f"{target}.{os.getpid()}"
    db = sqlite3.connect(temporary)
    tokenizer = "porter unicode61 remove_diacritics 2" if lang == "en" else "unicode61 remove_diacritics 2"
    db.execute(f"create virtual table sections using fts5(path unindexed, anchor unindexed, title, section, body, tokenize='{tokenizer}')")
    db.execute("create virtual table terms using fts5vocab(sections, 'row')")
    db.execute("create table meta(key text primary key, value text)")
    folder = os.path.join(ROOT, lang)
    for name in glob.iglob(folder + "/**/*.html", recursive=True):
        with open(name, encoding="utf-8", errors="replace") as f:
            source = f.read()
        found = TITLE.search(source)
        title = html.unescape(found.group(1)).removesuffix(" - ArchWiki") if found else ""
        path = os.path.relpath(name, folder)[:-5]
        # English also holds a few other languages' pages under hashed names.
        if lang == "en" and re.fullmatch(r"[0-9a-f]{32}", path) and title.endswith(")"):
            continue
        start = source.find(">", source.find('id="mw-content-text"')) + 1
        end = source.find('class="printfooter"', start)
        parts = HEADING.split(NOISE.sub(" ", source[start:end if end > 0 else None]))
        db.execute("insert into sections values (?,?,?,?,?)", (path, "", title, "", clean(parts[0])))
        for i in range(1, len(parts), 4):
            db.execute("insert into sections values (?,?,?,?,?)", (path, parts[i + 1], title, clean(parts[i + 2]), clean(parts[i + 3])))
    db.execute("insert into sections(sections) values ('optimize')")
    db.execute("insert into meta values ('stamp', ?)", (stamp(lang),))
    db.commit()
    db.close()
    os.replace(temporary, target)


def quoted(word):
    return '"' + word.replace('"', '""') + '"'


def term(word, last):
    if word in SAME:
        return "(" + " OR ".join(quoted(w) for w in SAME[word]) + ")"
    return quoted(word) + ("*" if last else "")


def lookup(db, words, joiner):
    match = f" {joiner} ".join(term(w, i == len(words) - 1) for i, w in enumerate(words))
    return db.execute(
        f"select path, anchor, title, section, snippet(sections, 4, '{OPEN}', '{CLOSE}', '…', 20), bm25(sections, 0, 0, 12, 5, 1) "
        "from sections where sections match ? order by 6 limit 300", (match,)).fetchall()


def rank(rows, query, words):
    """The best section of each page, and pages about the words ahead of pages that mention them."""
    pages = {}
    for path, anchor, title, section, snippet, score in rows:
        if path.startswith(("Category:", "Special:", "Talk:", "Template:")):
            continue
        name = title.lower()
        given = [w for w in words if any(s in WORD.findall(name) for s in SAME.get(w, [w]))]
        heard = [w for w in words if any(s in name for s in SAME.get(w, [w]))]
        points = 60 * len(given) + 25 * len(heard)
        if name == query:
            points += 1000
        elif name.startswith(query):
            points += 300
        if words and len(heard) == len(words):
            points += 250
        # "NVIDIA" before "NVIDIA/Tips and tricks", and an article before one about one laptop.
        points -= 10 * path.count("/")
        if path.startswith(("Laptop/", "Dell_", "Lenovo_", "HP_", "ASUS_", "Acer_")) and not given:
            points -= 40
        page = pages.setdefault(path, {"points": points, "sections": 0, "best": None, "path": path, "title": title})
        page["sections"] += 1
        phrase = " " in query and query in section.lower()
        fit = (phrase, sum(w in section.lower() for w in words), -score)
        if page["best"] is None or fit > page["best"]:
            page.update(best=fit, section=section, anchor=anchor, snippet=snippet, phrase=phrase, score=-score)
    for page in pages.values():
        # A page where the words come up section after section is about them.
        page["total"] = page["points"] + min(60, 3 * page["sections"]) + page["score"] + (200 if page["phrase"] else 0)
    out = []
    for page in sorted(pages.values(), key=lambda p: -p["total"])[:LIMIT]:
        name = page["title"].lower()
        about = all(any(s in name for s in SAME.get(w, [w])) for w in words)
        whole = name == query or (about and not page["phrase"])
        out.append({"path": page["path"], "title": page["title"], "snippet": page["snippet"],
                    "section": "" if whole else page["section"], "anchor": "" if whole else page["anchor"]})
    return out


def corrected(db, words):
    """The nearest words the wiki really has, for a query that found nothing."""
    fixed = []
    for word in words:
        if db.execute("select 1 from terms where term = ?", (word,)).fetchone():
            fixed.append(word)
            continue
        near = db.execute("select term, doc from terms where length(term) between ? and ? and substr(term, 1, 1) = ? and doc >= 3 order by doc desc limit 20000",
                          (len(word) - 2, len(word) + 2, word[:1])).fetchall()
        close = difflib.get_close_matches(word, [t for t, _ in near], n=1, cutoff=0.72)
        fixed.append(close[0] if close else word)
    return fixed


def search(lang, query):
    query = query.strip().lower()
    words = WORD.findall(query)
    meaningful = [w for w in words if w not in COMMON] or words
    answer = {"corrected": "", "results": []}
    if not words or not os.path.exists(index_path(lang)):
        return answer
    db = sqlite3.connect(f"file:{index_path(lang)}?mode=ro", uri=True)
    rows = lookup(db, meaningful, "AND")
    if not rows:
        fixed = corrected(db, meaningful)
        if fixed != meaningful:
            rows = lookup(db, fixed, "AND")
            if rows:
                answer["corrected"] = " ".join(fixed)
                query, meaningful = answer["corrected"], fixed
    if not rows and len(meaningful) > 1:
        rows = lookup(db, meaningful, "OR")
    answer["results"] = rank(rows, query, meaningful)
    return answer


if __name__ == "__main__":
    if sys.argv[1] == "build":
        build(sys.argv[2])
    elif sys.argv[1] == "search":
        print(json.dumps(search(sys.argv[2], sys.argv[3]), ensure_ascii=False))
