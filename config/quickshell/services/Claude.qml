pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// Claude Code in the island: one `claude -p` run per message, resumed by session id.
Singleton {
    id: root

    property var messages: []
    property string sessionId: ""
    property bool busy: false
    property string error: ""
    property bool installed: true
    property string pending: ""

    // The account, as `claude auth status` has it; signing in opens the browser like the VS Code extension does.
    property bool checked: false
    property bool loggedIn: false
    property string account: ""
    property string plan: ""
    property bool signingIn: false
    property string loginUrl: ""
    readonly property bool needsLogin: installed && checked && !loggedIn

    readonly property string bin: 'c=$(command -v claude || echo "$HOME/.local/bin/claude"); exec "$c" "$@" </dev/null'

    // Every Claude Code session on this desktop, and the permissions they ask for (scripts/claude-hook.py).
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR")) + "/vyntaris-claude"
    property var sessions: []
    property var asks: []
    readonly property var ask: asks[0] ?? null
    readonly property var working: sessions.filter(s => s.state === "working")
    readonly property var waiting: sessions.filter(s => s.state === "waiting")

    function refresh() { if (!scan.running) scan.running = true; else rescan = true; }
    property bool rescan: false

    function answer(decision) {
        const a = ask;
        if (!a) return;
        asks = asks.slice(1);
        Quickshell.execDetached(["sh", "-c", 'umask 077; printf %s "$2" > "$1.new" && mv "$1.new" "$1"', "sh",
                    runDir + "/answer-" + a.id, decision]);
    }

    // A real notification, kept in the list until read; for the island's chat a click brings it back.
    function notify(title, body, chat) {
        const plain = String(body ?? "").replace(/[`*_#>]/g, "").replace(/\s+/g, " ").trim().slice(0, 160);
        Quickshell.execDetached(["sh", "-c",
            'a=$(notify-send -a Claude -i utilities-terminal ${3:+-A default="$4"} -- "$1" "$2"); [ "$a" = default ] && qs -c vyntaris ipc call claude open',
            "sh", title, plain, chat ? "1" : "", Tr.t("Open")]);
    }

    function place(s) {
        const p = s.cwd.replace(Quickshell.env("HOME"), "~");
        return p.split("/").pop() || p;
    }

    Process {
        id: scan
        command: ["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in session-*.json ask-*.json; do [ -f "$f" ] && { cat "$f"; echo; }; done', "sh", root.runDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const before = {};
                for (const s of root.sessions) before[s.id] = s.state;
                const ses = [], asks = [];
                for (const line of text.split("\n")) {
                    let e;
                    try { e = JSON.parse(line); } catch (err) { continue; }
                    if (e.tool !== undefined) asks.push(e); else ses.push(e);
                }
                asks.sort((a, b) => a.id < b.id ? -1 : 1);
                for (const s of ses)
                    if (Panels.claudeOpen) continue;
                    else if (before[s.id] === "working" && s.state === "done")
                        root.notify(Tr.t("Claude is done"), s.title || root.place(s), false);
                    else if (before[s.id] !== "waiting" && s.state === "waiting")
                        root.notify(Tr.t("Claude is waiting for you"), s.message || root.place(s), false);
                root.sessions = ses;
                root.asks = asks;
                root.reloadWatched();
            }
        }
        onExited: if (root.rescan) { root.rescan = false; running = true; }
    }
    Component.onCompleted: refresh()

    // Slash commands: the ones about this chat are kept here (each message is a new `claude -p`, so a model
    // or effort set inside one wouldn't last), the ones that need a terminal say so, the rest go to Claude.
    property var commands: []
    property string chatModel: ""
    property string chatEffort: ""
    readonly property var terminalOnly: ["doctor", "color", "focus", "reload-plugins", "config", "agents", "mcp", "login", "logout", "permissions", "hooks", "ide", "theme", "vim", "terminal-setup", "status", "statusline", "exit"]
    function note(text) { messages = messages.concat([{ role: "note", text }]); }
    function command(text) {
        const m = text.match(/^\/(\S+)\s*(.*)$/);
        if (!m) return false;
        const name = m[1], arg = m[2].trim();
        if (name === "clear" || name === "new") { newChat(cwd); return true; }
        if (name === "resume") { browseWanted(); return true; }
        if (name === "usage") { messages = messages.concat([{ role: "user", text }]); usageNote = true; refreshUsage(true); return true; }
        if (name === "model" && arg) { chatModel = arg; messages = messages.concat([{ role: "user", text }]); note(Tr.f("Model for this chat: {0}", arg)); return true; }
        if (name === "effort" && arg) { chatEffort = arg; messages = messages.concat([{ role: "user", text }]); note(Tr.f("Effort for this chat: {0}", arg)); return true; }
        if (terminalOnly.includes(name)) {
            messages = messages.concat([{ role: "user", text }]);
            note(Tr.f("/{0} works only in the terminal: use the terminal button above.", name));
            return true;
        }
        return false;
    }

    function send(text) {
        text = (text ?? "").trim();
        if (!text) return;
        if (busy) { pending = text; return; }
        error = "";
        if (text.startsWith("/") && command(text)) return;
        messages = messages.concat([{ role: "user", text }, { role: "assistant", text: "", tools: [] }]);
        const args = ["-p", text, "--output-format", "stream-json", "--verbose"];
        if (sessionId) args.push("--resume", sessionId);
        if (chatModel) args.push("--model", chatModel);
        if (chatEffort) args.push("--effort", chatEffort);
        run.command = ["sh", "-c", 'cd "$1" && shift && ' + bin, "sh", workdir()].concat(args);
        busy = true;
        chatDoing = {};
        run.running = true;
    }

    function stop() { if (run.running) run.signal(15); }
    function newChat(folder) { stop(); messages = []; sessionId = ""; error = ""; pending = ""; cost = 0; cwd = folder ?? ""; chatModel = ""; chatEffort = ""; }

    // The plan's use, as `/usage` shows it; asked for without a session and without spending anything.
    property var usage: null
    property bool usageNote: false
    property real usageAt: 0
    function refreshUsage(now) {
        if (!loggedIn || usageRun.running || (!now && Date.now() - usageAt < 120000)) return;
        usageAt = Date.now();
        usageRun.command = ["sh", "-c", 'cd "$1" && shift && ' + bin, "sh", workdir(),
                            "-p", "/usage", "--no-session-persistence", "--output-format", "stream-json", "--verbose"];
        usageRun.running = true;
    }
    function takeUsage(text) {
        const line = re => { const m = text.match(re); return m ? { used: Number(m[1]) / 100, resets: (m[2] ?? "").replace(/\s*\(.*\)$/, "") } : null; };
        const session = line(/Current session:\s*(\d+)% used(?:\s*·\s*resets\s*([^\n]+))?/);
        const week = line(/Current week \(all models\):\s*(\d+)% used(?:\s*·\s*resets\s*([^\n]+))?/);
        if (session || week) usage = { session, week };
        if (usageNote) { usageNote = false; note(text.split("\n\nWhat's contributing")[0].trim()); }
    }

    // The folder this chat works in, what it costs, and how much of the plan is used (from Claude's own events).
    property string cwd: ""
    property string model: ""
    property real cost: 0
    function workdir() { return (cwd || Config.claude?.workdir || Quickshell.env("HOME")).replace(/"/g, ""); }
    function folderName(p) {
        const home = Quickshell.env("HOME");
        return p === home ? "~" : String(p).replace(home, "~");
    }

    // Every session on this computer (scripts/claude-sessions.py), to go on with one here.
    signal browseWanted()
    signal draftWanted(string text)
    property var history: []
    property bool loadingHistory: false
    function loadSessions() { if (!listing.running) { history = []; loadingHistory = true; listing.running = true; } }
    function resume(s) {
        stop();
        messages = [];
        error = "";
        cost = 0;
        sessionId = s.id;
        cwd = s.cwd;
        shown.past = [];
        shown.command = ["python3", "-I", Quickshell.shellPath("scripts/claude-sessions.py"), "show", s.id];
        shown.running = true;
    }
    function openInTerminal() {
        const id = sessionId.replace(/[^A-Za-z0-9-]/g, "");
        Config.runInTerminal('cd "' + workdir() + '" && claude' + (id ? " --resume " + id : ""));
    }
    function checkAuth() { if (!status.running) status.running = true; }
    function login(console) {
        if (signingIn) return;
        loginUrl = "";
        error = "";
        signingIn = true;
        signIn.command = ["sh", "-c", bin.replace(" </dev/null", ""), "sh", "auth", "login"].concat(console ? ["--console"] : []);
        signIn.running = true;
    }
    function sendCode(code) { if (signIn.running && code.trim()) signIn.write(code.trim() + "\n"); }
    function cancelLogin() { if (signIn.running) signIn.signal(15); }
    function logout() { Quickshell.execDetached(["sh", "-c", bin, "sh", "auth", "logout"]); loggedIn = false; account = ""; recheck.restart(); }
    function install() { Config.runInTerminal("curl -fsSL https://claude.ai/install.sh | bash; " + Config.enterToClose(true)); }

    function last() { return messages[messages.length - 1]; }
    function touch() { messages = messages.slice(); }

    // What a session is doing right now, for the island: {verb, what} from scripts/claude-hook.py or this chat.
    property var chatDoing: ({})
    function doingText(d) {
        const w = d?.what ?? "";
        switch (d?.verb) {
        case "run": return Tr.f("Running {0}", w);
        case "edit": return Tr.f("Editing {0}", w);
        case "write": return Tr.f("Writing {0}", w);
        case "read": return Tr.f("Reading {0}", w);
        case "search": return Tr.f("Searching {0}", w);
        case "web": return Tr.f("On the web: {0}", w);
        case "agent": return w || Tr.t("Working in parallel");
        case "plan": return Tr.t("Planning");
        case "compact": return Tr.t("Compacting the conversation");
        case "tool": return w;
        default: return Tr.t("Thinking…");
        }
    }
    function doingOf(name, input) {
        const base = p => String(p ?? "").replace(/\/+$/, "").split("/").pop();
        if (name === "Bash") return { verb: "run", what: String(input.command ?? "").replace(/\s+/g, " ").slice(0, 60) };
        if (name === "Edit" || name === "MultiEdit" || name === "NotebookEdit") return { verb: "edit", what: base(input.file_path ?? input.notebook_path) };
        if (name === "Write") return { verb: "write", what: base(input.file_path) };
        if (name === "Read") return { verb: "read", what: base(input.file_path) };
        if (name === "Grep" || name === "Glob") return { verb: "search", what: String(input.pattern ?? "").slice(0, 40) };
        if (name === "WebFetch" || name === "WebSearch") return { verb: "web", what: String(input.query ?? input.url ?? "").slice(0, 40) };
        if (name === "Task" || name === "Agent") return { verb: "agent", what: String(input.description ?? "").slice(0, 40) };
        if (name === "TodoWrite") return { verb: "plan", what: "" };
        return { verb: "tool", what: name };
    }

    function tool(name, input) {
        const home = Quickshell.env("HOME");
        const path = p => String(p ?? "").replace(home, "~");
        if (name === "Bash") return { icon: "terminal", text: input.command ?? "" };
        if (name === "Edit" || name === "Write" || name === "MultiEdit" || name === "NotebookEdit")
            return { icon: "edit", text: path(input.file_path ?? input.notebook_path) };
        if (name === "Read") return { icon: "eye", text: path(input.file_path) };
        if (name === "Glob" || name === "Grep") return { icon: "search", text: input.pattern ?? "" };
        if (name === "WebFetch" || name === "WebSearch") return { icon: "globe", text: input.url ?? input.query ?? "" };
        return { icon: "settings", text: name };
    }

    function take(e) {
        if (e.session_id) sessionId = e.session_id;
        if (e.type === "system" && e.subtype === "init") {
            if (e.model) model = e.model;
            if (e.slash_commands) commands = e.slash_commands;
        }
        if (e.type === "system" && e.status === "compacting") chatDoing = { verb: "compact" };
        if (e.type === "system" && e.subtype === "compact_boundary") {
            const c = e.compact_metadata ?? {};
            const k = n => Math.round((n ?? 0) / 1000) + "k";
            messages = messages.slice(0, -1).concat([{ role: "note", text: Tr.f("Conversation compacted: {0} → {1} tokens", k(c.pre_tokens), k(c.post_tokens)) }], messages.slice(-1));
        }
        if (e.type === "rate_limit_event") {
            const w = e.rate_limit_info?.unifiedWindows ?? {};
            const part = (win, was) => win?.utilization !== undefined ? { used: win.utilization, resets: was?.resets ?? "" } : was;
            usage = { session: part(w.five_hour, usage?.session), week: part(w.seven_day, usage?.week) };
        }
        let m = last();
        if (!m || m.role !== "assistant") return;
        if (e.type === "assistant") {
            // in the order it happened: text after tools, or tools after text, start a message of their own
            const fresh = () => { m = { role: "assistant", text: "", tools: [] }; messages.push(m); };
            for (const c of e.message?.content ?? []) {
                if (c.type === "text") { if (m.tools.length) fresh(); m.text += (m.text ? "\n\n" : "") + c.text; }
                else if (c.type === "tool_use") { if (m.text) fresh(); m.tools.push(tool(c.name, c.input ?? {})); chatDoing = doingOf(c.name, c.input ?? {}); }
            }
            touch();
        } else if (e.type === "result") {
            if (e.is_error) {
                const r = String(e.result ?? e.subtype ?? "");
                if (/log ?in|auth|api key/i.test(r)) { loggedIn = false; checkAuth(); }
                else error = r;
            } else if (!m.text && e.result) {
                m.text = e.result;
            }
            if (e.total_cost_usd !== undefined) { m.cost = e.total_cost_usd; cost += e.total_cost_usd; }
            touch();
        }
    }

    Process {
        id: run
        environment: ({ VYNTARIS_ISLAND: "1" })
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                root.take(e);
            }
        }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.busy = false;
            if (code === 127) root.installed = false;
            else if (code !== 0 && code !== 143 && !root.error && !root.needsLogin) {
                const t = err.text.trim();
                if (/log ?in|auth/i.test(t)) { root.loggedIn = false; root.checkAuth(); }
                else root.error = t.split("\n").pop() || Tr.t("Claude stopped unexpectedly");
            }
            const m = root.last();
            if (m && m.role === "assistant" && !m.text && !m.tools.length) root.messages = root.messages.slice(0, -1);
            else if (code === 0 && m?.role === "assistant" && !Panels.claudeOpen) root.notify(Tr.t("Claude is done"), m.text, true);
            root.refreshUsage(true);
            if (root.pending) { const p = root.pending; root.pending = ""; root.send(p); }
        }
    }

    Process {
        id: usageRun
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.type === "system" && e.subtype === "init" && e.slash_commands) root.commands = e.slash_commands;
                if (e.type === "result" && typeof e.result === "string") root.takeUsage(e.result);
            }
        }
    }

    // A session running elsewhere (VS Code, a terminal), watched from the island: its conversation as it goes, read
    // from its transcript at each of its steps (the hook's events) and every 2 s while the panel shows it.
    property string watching: ""
    property var watched: []
    property var watchedMeta: ({})
    readonly property var watchedSession: sessions.find(s => s.id === watching) ?? null
    readonly property string watchedState: watchedSession?.state ?? "done"
    readonly property string watchedPlace: watchedMeta.entrypoint === "claude-vscode" ? "VS Code"
        : (watchedMeta.entrypoint ?? "").startsWith("sdk") ? Tr.t("another app") : Tr.t("a terminal")
    function watch(id) {
        if (watching !== id) { watched = []; watchedMeta = {}; }
        watching = id;
        reloadWatched();
    }
    function unwatch() { watching = ""; watched = []; watchedMeta = {}; }
    function continueHere() {
        const id = watching, folder = watchedMeta.cwd || watchedSession?.cwd || "";
        unwatch();
        resume({ id, cwd: folder });
    }
    property bool watchAgain: false
    function reloadWatched() {
        if (!watching) return;
        if (watchRead.running) { watchAgain = true; return; }
        watchRead.past = [];
        watchRead.command = ["python3", "-I", Quickshell.shellPath("scripts/claude-sessions.py"), "show", watching];
        watchRead.running = true;
    }
    Process {
        id: watchRead
        property var past: []
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (err) { return; }
                if (m.role === "meta") { root.watchedMeta = m; return; }
                if (m.role === "assistant") m.tools = (m.tools ?? []).map(t => root.tool(t.name, t.input ?? {}));
                watchRead.past.push(m);
            }
        }
        onExited: {
            if (root.watching) root.watched = watchRead.past;
            if (root.watchAgain) { root.watchAgain = false; root.reloadWatched(); }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.watching !== "" && Panels.claudeOpen
        onTriggered: root.reloadWatched()
    }

    Process {
        id: listing
        command: ["python3", "-I", Quickshell.shellPath("scripts/claude-sessions.py"), "list"]
        stdout: SplitParser {
            onRead: line => { try { root.history = root.history.concat([JSON.parse(line)]); } catch (err) {} }
        }
        onExited: root.loadingHistory = false
    }
    Process {
        id: shown
        property var past: []
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (err) { return; }
                if (m.role === "meta") return;
                if (m.role === "assistant") m.tools = (m.tools ?? []).map(t => root.tool(t.name, t.input ?? {}));
                shown.past.push(m);
            }
        }
        onExited: root.messages = shown.past.concat(root.messages)
    }

    Process {
        id: status
        running: true
        command: ["sh", "-c", root.bin, "sh", "auth", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let a;
                try { a = JSON.parse(text); } catch (err) { return; }
                root.loggedIn = !!a.loggedIn;
                root.account = a.email ?? "";
                const p = a.subscriptionType ?? (a.authMethod === "console" ? "Console" : "");
                root.plan = p.charAt(0).toUpperCase() + p.slice(1);
            }
        }
        onExited: code => {
            root.installed = code !== 127;
            if (code === 1) root.loggedIn = false;
            root.checked = true;
        }
    }
    Timer { id: recheck; interval: 1500; onTriggered: root.checkAuth() }

    Process {
        id: signIn
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                const m = line.match(/https:\/\/\S+/);
                if (m) root.loginUrl = m[0];
            }
        }
        onExited: code => {
            root.signingIn = false;
            stdinEnabled = true;
            root.checkAuth();
        }
    }
}
