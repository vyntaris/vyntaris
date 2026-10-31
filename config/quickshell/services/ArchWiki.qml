pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/vyntaris/wiki"
    readonly property string script: Quickshell.shellPath("scripts/wiki.sh")
    readonly property string engine: Quickshell.shellPath("scripts/wiki-search.py")

    property bool checked: false
    property var languages: []
    readonly property bool installed: languages.length > 0
    property bool installing: false

    property string language: ""
    property var pages: []
    property bool loading: false
    property var recent: []

    property string query: ""
    property var found: null
    property string corrected: ""
    property bool searching: false
    property bool indexing: false

    readonly property var starters: ["Installation_guide", "General_recommendations", "Pacman", "Systemd", "Network_configuration", "System_maintenance"]
        .map(path => pages.find(p => p.path === path)).filter(p => p)

    function nameOf(code) {
        if (code === "en") return "English";
        const name = Qt.locale(code.replace("zh-hans", "zh_CN").replace("zh-hant", "zh_TW")).nativeLanguageName;
        return name ? name.charAt(0).toUpperCase() + name.slice(1) : code;
    }

    function pick(code) {
        if (code === language) return;
        language = code;
        pages = [];
        found = null;
        corrected = "";
        saveState();
        loadPages();
    }

    function search(text) {
        const q = text.trim().toLowerCase();
        if (!q) return [];
        const words = q.split(/\s+/);
        const found = [];
        for (const p of pages) {
            const t = p.title.toLowerCase();
            if (!words.every(w => t.includes(w))) continue;
            const score = t === q ? 100 : t.startsWith(q) ? 80 : new RegExp("\\b" + words[0].replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).test(t) ? 60 : 40;
            found.push({ page: p, score });
        }
        found.sort((a, b) => b.score - a.score || a.page.title.length - b.page.title.length);
        return found.map(f => f.page);
    }

    // The engine's answer; titles alone answer at once until it comes, or while the index is being made.
    readonly property var results: found ?? search(query)

    function setQuery(text) {
        if (text === query) return;
        query = text;
        if (!text.trim()) { found = null; corrected = ""; return; }
        engineTimer.restart();
    }

    function url(page) {
        return "file://" + folder + "/" + language + "/" + page.path.split("/").map(encodeURIComponent).join("/") + ".html"
            + (page.anchor ? "#" + encodeURIComponent(page.anchor) : "");
    }

    // A snippet from the engine as text to show: its marks around the words become the given colour.
    function marked(snippet, colour) {
        return (snippet ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/\x02/g, `<b><font color="${colour}">`).replace(/\x03/g, "</font></b>");
    }
    function plain(snippet) {
        return (snippet ?? "").replace(/[\x02\x03]/g, "");
    }

    function open(page) {
        const known = recent.filter(r => r.path !== page.path || r.anchor !== page.anchor || r.language !== language);
        recent = [{ title: page.title, section: page.section ?? "", anchor: page.anchor ?? "", path: page.path, language: language }].concat(known).slice(0, 6);
        saveState();
        painter.target = url(page);
        painter.command = ["sh", script, "theme", folder, colours(), Quickshell.shellPath("assets/wiki.css")];
        painter.running = true;
    }

    function colours() {
        const t = Theme;
        return `:root { color-scheme: ${t.isDark ? "dark" : "light"}; --wiki-base: ${t.base}; --wiki-mantle: ${t.mantle}; --wiki-crust: ${t.crust}; `
            + `--wiki-surface: ${t.surface0}; --wiki-line: ${t.surface1}; --wiki-text: ${t.text}; --wiki-soft: ${t.subtext0}; `
            + `--wiki-accent: ${t.accent}; --wiki-on-accent: ${t.textOnAccent}; --wiki-error: ${t.error}; }`;
    }

    function install() {
        if (installing) return;
        installing = true;
        installer.running = true;
    }

    function clean(title) {
        return title.replace(/&amp;/g, "&").replace(/&#0?39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">");
    }

    function loadPages() {
        if (!language) return;
        loading = true;
        pagesProc.running = false;
        pagesProc.command = ["sh", script, "pages", language];
        pagesProc.running = true;
        indexing = true;
        indexer.command = ["nice", "-n", "19", engine, "build", language];
        indexer.running = true;
    }

    function saveState() {
        stateFile.setText(JSON.stringify({ language, recent }));
    }

    function settle(saved) {
        const has = code => languages.some(l => l.code === code && l.count >= 20);
        language = languages.some(l => l.code === saved) ? saved : has(Tr.lang) ? Tr.lang : "en";
        loadPages();
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("wiki.json")
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.recent = d.recent ?? [];
                root.saved = d.language ?? "";
            } catch (e) {}
            if (root.checked) root.settle(root.saved);
        }
    }
    property string saved: ""

    function check() {
        languagesProc.running = false;
        languagesProc.running = true;
    }
    Component.onCompleted: check()

    Process {
        id: languagesProc
        command: ["sh", root.script, "languages"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.languages = text.split("\n").filter(l => l).map(l => {
                    const [code, count] = l.split("\t");
                    return { code, count: Number(count) };
                }).sort((a, b) => b.count - a.count);
                root.checked = true;
                if (root.installed && !root.language) root.settle(root.saved);
            }
        }
    }

    Process {
        id: pagesProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.pages = text.split("\n").filter(l => l).map(l => {
                    const cut = l.indexOf("\t");
                    return { path: l.slice(0, cut), title: root.clean(l.slice(cut + 1)) };
                }).filter(p => !(/^[0-9a-f]{32}$/.test(p.path) && /\([^)]+\)$/.test(p.title) && root.language === "en"));
                root.loading = false;
            }
        }
    }

    Process {
        id: indexer
        onExited: {
            root.indexing = false;
            if (root.query.trim()) engineTimer.restart();
        }
    }

    Timer {
        id: engineTimer
        interval: 60
        onTriggered: {
            if (root.indexing) return;
            root.searching = true;
            engineProc.running = false;
            engineProc.asked = root.query;
            engineProc.command = [root.engine, "search", root.language, root.query];
            engineProc.running = true;
        }
    }
    Process {
        id: engineProc
        property string asked
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                if (engineProc.asked !== root.query) return;
                try {
                    const answer = JSON.parse(text);
                    root.found = answer.results;
                    root.corrected = answer.corrected;
                } catch (e) {}
            }
        }
    }

    Process {
        id: painter
        property string target
        onExited: code => { if (code === 0) Config.launch(["xdg-open", target]); }
    }

    Process {
        id: installer
        command: ["pkexec", "pacman", "-S", "--needed", "--noconfirm", "arch-wiki-docs"]
        onExited: { root.installing = false; root.check(); }
    }
}
