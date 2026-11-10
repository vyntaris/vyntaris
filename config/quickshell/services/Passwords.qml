pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// Passwords kept by pass, in the island. A password field in any app opens it, searched for that site.
Singleton {
    id: root

    readonly property string tool: Quickshell.shellPath("scripts/pass.sh")
    readonly property bool installed: hasPass.found
    property bool ready: false
    property var entries: []
    property bool locked: false
    property bool wrong: false
    property bool busy: false
    property string failure: ""

    // The field that opened the island: its site (or app), and whether a username field comes before it.
    property string site: ""
    property string app: ""
    property bool userField: false
    property bool userEmpty: false

    function refresh() {
        statusProc.running = false; statusProc.running = true;
        listProc.running = false; listProc.running = true;
    }
    // Known from the start, for Firefox's fields and logins before the island was ever opened.
    Component.onCompleted: refresh()

    // The entries for this site first: "github.com/me", "github.com", "work/github.com".
    function matches(entry, place) {
        if (!place) return false;
        const e = entry.toLowerCase(), p = place.toLowerCase();
        return e.split("/").some(part => part === p || p.endsWith("." + part) || part.endsWith("." + p));
    }
    function search(query) {
        const q = query.trim().toLowerCase();
        const hits = entries.filter(e => !q || e.toLowerCase().includes(q) || matches(e, q));
        const near = hits.filter(e => matches(e, site));
        return near.concat(hits.filter(e => !near.includes(e)));
    }

    function open(fromField) {
        if (!fromField) { site = ""; app = ""; userField = false; userEmpty = false; atUser = false; }
        refresh();
        Panels.passwordsOpen = true;
    }

    // What to do once the passphrase is in: fill, copy or show the entry asked for.
    property var pending: null
    function act(kind, name, extra) {
        if (busy) return;
        pending = { kind, name, extra: extra ?? "" };
        failure = "";
        const args = kind === "fill" ? ["fill", name, atUser ? "here" : extra ? "user" : ""]
            : kind === "copy" ? ["copy", name, extra]
            : ["show", name];
        if (kind === "fill") Panels.passwordsOpen = false;
        busy = true;
        actProc.command = [tool].concat(args);
        actProc.running = true;
    }
    function fill(name) { act("fill", name, userField && userEmpty); }
    function copy(name, what) { act("copy", name, what ?? ""); }
    // An entry read for changing it: its name and text together.
    signal opened(string name, string text)
    function show(name) { act("show", name); }

    // The entry's text and the exit come in either order.
    Process {
        id: actProc
        property string text: ""
        property int code: -1
        onStarted: { text = ""; code = -1; }
        stdout: StdioCollector { onStreamFinished: { actProc.text = text; if (actProc.code >= 0) root.done(); } }
        onExited: code => { actProc.code = code; if (code !== 0 || actProc.text || !root.pending || root.pending.kind !== "show") root.done(); }
    }
    function done() {
        busy = false;
        const p = pending;
        if (!p) return;
        if (actProc.code === 5) {
            // Asked for after the master password; the island comes back if picking had closed it.
            locked = true;
            Panels.passwordsOpen = true;
            return;
        }
        pending = null;
        if (actProc.code !== 0) { failure = Tr.t("That entry couldn't be read."); return; }
        if (p.kind === "show") opened(p.name, actProc.text);
        if (p.kind === "copy") { Panels.passwordsOpen = false; Osd.show(p.extra === "login" ? "username-copied" : "password-copied"); }
    }

    function unlock(phrase) {
        if (busy || !phrase) return;
        busy = true;
        wrong = false;
        unlockProc.input = phrase;
        unlockProc.running = true;
    }
    Process {
        id: unlockProc
        property string input: ""
        command: [root.tool, "unlock"]
        stdinEnabled: true
        onStarted: { write(input + "\n"); input = ""; stdinEnabled = false; }
        onExited: code => {
            unlockProc.stdinEnabled = true;
            root.busy = false;
            if (code !== 0) { root.wrong = true; return; }
            root.locked = false;
            const p = root.pending;
            root.pending = null;
            if (p) root.act(p.kind, p.name, p.extra);
        }
    }
    function lock() {
        Quickshell.execDetached([tool, "lock"]);
        locked = true;
    }

    function setup(phrase) {
        if (busy || !phrase) return;
        busy = true;
        failure = "";
        setupProc.input = phrase;
        setupProc.running = true;
    }
    Process {
        id: setupProc
        property string input: ""
        command: [root.tool, "setup"]
        stdinEnabled: true
        onStarted: { write(input + "\n"); input = ""; stdinEnabled = false; }
        onExited: code => {
            setupProc.stdinEnabled = true;
            root.busy = false;
            if (code !== 0) root.failure = Tr.t("The password store couldn't be set up.");
            root.locked = false;
            root.refresh();
        }
    }

    // A new or changed entry: the password, then "login: name" and "url: site" lines.
    function save(name, password, login, url, replacing) {
        name = name.trim().replace(/^\/+|\/+$/g, "");
        if (!name || !password) return;
        const lines = [password];
        if (login.trim()) lines.push("login: " + login.trim());
        if (url.trim()) lines.push("url: " + url.trim());
        saveProc.input = lines.join("\n");
        saveProc.replacing = replacing && replacing !== name ? replacing : "";
        saveProc.command = [tool, "save", name];
        saveProc.running = true;
    }
    Process {
        id: saveProc
        property string input: ""
        property string replacing: ""
        stdinEnabled: true
        onStarted: { write(input + "\n"); input = ""; stdinEnabled = false; }
        onExited: code => {
            saveProc.stdinEnabled = true;
            if (code !== 0) { root.failure = Tr.t("The password wasn't saved."); return; }
            if (saveProc.replacing) Quickshell.execDetached([root.tool, "delete", saveProc.replacing]);
            root.refresh();
        }
    }
    function remove(name) {
        removeProc.command = [tool, "delete", name];
        removeProc.running = true;
    }
    Process { id: removeProc; onExited: root.refresh() }

    // A login Firefox just sent that isn't saved, or is saved with another password: offered in the island.
    property var offer: null
    function takeOffer() { offerRead.running = false; offerRead.running = true; }
    Process {
        id: offerRead
        command: ["sh", "-c", 'f="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vyntaris-passwords/offer.json"; cat "$f" && rm -f "$f"']
        stdout: StdioCollector {
            onStreamFinished: {
                let o;
                try { o = JSON.parse(text); } catch (e) { return; }
                const site = (o.site || "").replace(/^www\./, "");
                if (!site || !o.password || !root.ready || (Config.passwords.never ?? []).includes(site)) return;
                offerCheck.login = { site, user: o.user || "", password: o.password };
                offerCheck.running = false;
                offerCheck.command = [root.tool, "check", site];
                offerCheck.running = true;
            }
        }
    }
    Process {
        id: offerCheck
        property var login: null
        stdinEnabled: true
        onStarted: { write(login.user + "\n" + login.password + "\n"); stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                const [answer, name] = [text.trim().split(" ")[0], text.trim().split(" ").slice(1).join(" ")];
                const l = offerCheck.login;
                offerCheck.stdinEnabled = true;
                if (!l || (answer !== "new" && answer !== "changed")) return;
                root.offer = { site: l.site, user: l.user, password: l.password, name, update: answer === "changed" };
                offerTimer.restart();
            }
        }
    }
    Timer { id: offerTimer; interval: 30000; onTriggered: root.offer = null }
    function keepOffer(hovered) { if (hovered) offerTimer.stop(); else offerTimer.restart(); }
    function saveOffer() {
        const o = offer;
        offer = null;
        if (o) save(o.name, o.password, o.user, o.site, "");
    }
    function never() {
        if (offer) { Config.passwords.never = (Config.passwords.never ?? []).concat([offer.site]); Config.saveSoon(); }
        offer = null;
    }

    signal generated(string password)
    function generate() { genProc.running = false; genProc.running = true; }
    Process {
        id: genProc
        command: [root.tool, "generate"]
        stdout: StdioCollector { onStreamFinished: root.generated(text.trim()) }
    }

    Process {
        id: statusProc
        command: [root.tool, "status"]
        stdout: StdioCollector { onStreamFinished: root.ready = text.trim() === "ready" }
    }
    Process {
        id: listProc
        command: [root.tool, "list"]
        stdout: StdioCollector { onStreamFinished: root.entries = text.split("\n").filter(l => l) }
    }
    Process {
        id: hasPass
        property bool found: false
        running: true
        command: ["sh", "-c", "command -v pass"]
        onExited: code => found = code === 0
    }

    // The screen locking locks the passwords too.
    Connections {
        target: LockState
        function onLockedChanged() { if (LockState.locked) root.lock(); }
    }

    // A username field in Firefox (from the extension): the island, only where there's something to fill.
    function atUserField(site) {
        site = site.replace(/^www\./, "");
        if (!Config.passwords.autoOpen || !ready || LockState.locked || Panels.anyIslandPanel) return;
        if (quiet.running && site === lastPlace) return;
        if (!entries.some(e => matches(e, site))) return;
        lastPlace = site;
        quiet.restart();
        root.site = site;
        root.app = "firefox";
        userField = true;
        userEmpty = true;
        atUser = true;
        open(true);
    }
    property bool atUser: false

    // A password field anywhere: the island, searched for it. Not again for the same place for a while
    // (filling it, or Esc, gives the field the focus again).
    property string lastPlace: ""
    Timer { id: quiet; interval: 120000 }
    Process {
        id: watch
        running: Config.passwords.autoOpen && root.installed && !LockState.locked
        command: ["python3", "-u", Quickshell.shellPath("scripts/pass-watch.py")]
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.error !== undefined || !e.empty) return;
                const place = e.site || e.app;
                if (quiet.running && place === root.lastPlace) return;
                if (Panels.anyIslandPanel || LockState.locked) return;
                root.lastPlace = place;
                quiet.restart();
                root.site = e.site || "";
                root.app = e.app || "";
                root.userField = !!e.user;
                root.userEmpty = !!e.userEmpty;
                root.atUser = false;
                root.open(true);
            }
        }
    }
}
