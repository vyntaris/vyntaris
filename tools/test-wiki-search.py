#!/usr/bin/env python3
"""The Arch Wiki's search engine, on a small wiki made here: it needs neither the real one nor a desktop."""
import glob
import importlib.util
import os
import pathlib
import sys
import tempfile

work = tempfile.mkdtemp()
os.environ["ARCH_WIKI_ROOT"] = work + "/html"
os.environ["XDG_CACHE_HOME"] = work + "/cache"
spec = importlib.util.spec_from_file_location("engine", pathlib.Path(__file__).parent.parent / "config/quickshell/scripts/wiki-search.py")
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)

PAGES = {
    "Pacman": ("pacman", "The package manager. Installing packages with pacman, many times over.", [("Parallel_downloads", "Parallel downloads", "Fetch several files at once."), ("Usage", "Usage", "Run it.")]),
    "Parallels_Desktop": ("Parallels Desktop", "A virtual machine with parallels and many downloads, downloads, downloads.", []),
    "NVIDIA": ("NVIDIA", "The driver for the cards.", [("Installation", "Installation", "Install the nvidia driver.")]),
    "NVIDIA/Tips_and_tricks": ("NVIDIA/Tips and tricks", "More about nvidia, nvidia, nvidia.", []),
    "Network_configuration/Wireless": ("Network configuration/Wireless", "Setting up wireless cards.", []),
    "Dual_boot_with_Windows": ("Dual boot with Windows", "Windows next to Arch.", [("Troubleshooting", "Troubleshooting", "When boot fails with windows.")]),
    "0123456789abcdef0123456789abcdef": ("Pacman (Latviešu)", "Pacman latviski.", []),
    "Category:Wireless": ("Category:Wireless", "Wireless wireless wireless.", []),
    "Restic": ("Restic", "Backups.", [("systemd_timer", "systemd timer", "Run it with a systemd timer.")]),
    "Systemd/Timers": ("systemd/Timers", "Timers are systemd units.", [("Monotonic", "Monotonic timers", "A systemd timer that counts."), ("Realtime", "Realtime timers", "Another timer in systemd.")]),
}
for path, (title, intro, sections) in PAGES.items():
    file = pathlib.Path(work, "html/en", path + ".html")
    file.parent.mkdir(parents=True, exist_ok=True)
    body = "".join(f'<div class="mw-heading"><h2 id="{a}">{h}</h2></div><p>{t}</p>' for a, h, t in sections)
    file.write_text(f'<title>{title} - ArchWiki</title><div id="mw-content-text"><p>{intro}</p>{body}</div><div class="printfooter"></div>')
engine.build("en")

failed = 0


def expect(query, title, section="", fixed=""):
    global failed
    answer = engine.search("en", query)
    first = answer["results"][0] if answer["results"] else {}
    got = (first.get("title"), first.get("section", ""), answer["corrected"])
    good = got == (title, section, fixed)
    print(("  ok   " if good else "  FAIL ") + f"{query!r} -> {got}")
    failed += not good


expect("pacman", "pacman")
expect("pacmna", "pacman", fixed="pacman")
expect("parallel downloads", "pacman", "Parallel downloads")
expect("installing packages", "pacman")
expect("nvidia", "NVIDIA")
expect("install nvidia driver", "NVIDIA", "Installation")
expect("wifi not working", "Network configuration/Wireless")
expect("how to dual boot windows", "Dual boot with Windows")
expect("pac", "pacman")
expect("sytemd timer", "systemd/Timers", fixed="systemd timer")
if engine.search("en", "zzzzqqq")["results"]:
    print("  FAIL nonsense found something")
    failed += 1
if any(r["title"].endswith("(Latviešu)") for r in engine.search("en", "latviski")["results"]):
    print("  FAIL another language's page in English")
    failed += 1
if engine.search("de", "pacman")["ready"]:
    print("  FAIL a language with no index calls itself ready")
    failed += 1
pathlib.Path(engine.index_path("en") + ".12345").write_text("cut off")
pathlib.Path(work, "html/en").touch()
engine.build("en")
if glob.glob(engine.index_path("en") + ".*"):
    print("  FAIL an index cut off halfway stays behind")
    failed += 1
if any("mw-content" in r["snippet"] for r in engine.search("en", "manager")["results"]):
    print("  FAIL markup in a snippet")
    failed += 1
print(":: all fine" if not failed else f":: {failed} failed")
sys.exit(1 if failed else 0)
