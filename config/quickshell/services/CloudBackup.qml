pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property bool connected: false
    property bool reconnect: false
    property bool running: false
    property real last: 0
    property string result: ""
    property string error: ""
    property real used: -1
    property real total: -1
    property bool known: false

    property string now: ""
    readonly property bool signingIn: now === "connecting"
    readonly property bool backingUp: now.startsWith("backing-up")
    readonly property real progress: backingUp ? Math.max(0, Math.min(100, parseInt(now.split(" ")[1]) || 0)) / 100 : -1
    readonly property string folder: backingUp ? now.split(" ").slice(2).join(" ") : ""
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-cloud-backup/now"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const line = text().trim();
            const was = root.now;
            root.now = line.startsWith("done") ? "" : line;
            if (was && !root.now) root.refresh();
        }
    }

    readonly property var system: [
        { id: "documents", label: Tr.t("Documents") }, { id: "pictures", label: Tr.t("Pictures") },
        { id: "desktop", label: Tr.t("Desktop") }, { id: "music", label: Tr.t("Music") },
        { id: "videos", label: Tr.t("Videos") }, { id: "download", label: Tr.t("Downloads") },
    ]
    property var others: []
    readonly property var choices: system.concat(others)
    readonly property var picked: Config.cloudBackup.folders.split(",").filter(f => f)
    function pick(id, on) {
        const now = choices.map(c => c.id).filter(c => c === id ? on : picked.includes(c));
        Config.cloudBackup.folders = now.join(",");
        Config.saveSoon();
    }

    readonly property var whens: [
        { value: "startup", label: Tr.t("At every start") }, { value: "shutdown", label: Tr.t("At shutdown") },
        { value: "manual", label: Tr.t("Only by hand") },
    ]
    readonly property string when: ["startup", "shutdown", "manual"].includes(Config.cloudBackup.when) ? Config.cloudBackup.when : "startup"
    function setWhen(v) {
        Config.cloudBackup.when = v;
        Config.saveSoon();
    }

    function size(b) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
        return b.toFixed(i === 0 ? 0 : 1) + " " + units[i];
    }

    function refresh() {
        if (!status.running) status.running = true;
        if (!homeDirs.running) homeDirs.running = true;
    }

    function connect() {
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", "--unit=vyntaris-cloud-connect",
                                 "vyntaris-cloud-backup", "connect"]);
        watch.restart();
    }
    function disconnect() {
        Quickshell.execDetached(["sh", "-c", "vyntaris-cloud-backup disconnect"]);
        connected = false; last = 0; result = ""; error = ""; used = -1; total = -1;
    }
    function stop() {
        Quickshell.execDetached(["vyntaris-cloud-backup", "stop"]);
        running = false;
        watch.restart();
    }
    function browse() {
        Quickshell.execDetached(["vyntaris-cloud-backup", "browse"]);
    }
    function backUpNow() {
        Quickshell.execDetached(["systemd-run", "--user", "--collect", "--quiet", "--unit=vyntaris-cloud-backup-now",
                                 "--nice=19", "-p", "IOSchedulingClass=idle", "vyntaris-cloud-backup", "run", "--now"]);
        running = true;
        watch.restart();
    }

    Process {
        id: status
        command: ["vyntaris-cloud-backup", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s;
                try { s = JSON.parse(text); } catch (e) { return; }
                root.connected = s.connected; root.reconnect = s.reconnect === true; root.running = s.running; root.last = s.last;
                root.result = s.result; root.error = s.error; root.used = s.used; root.total = s.total;
                root.known = true;
            }
        }
    }

    Process {
        id: homeDirs
        command: ["sh", "-c", `skip="$(for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS TEMPLATES PUBLICSHARE; do xdg-user-dir $d; done)"
            find "$HOME" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '%f\\n' | sort -f | while IFS= read -r n; do
                printf '%s\\n' "$skip" | grep -qxF "$HOME/$n" || printf '%s\\n' "$n"
            done`]
        stdout: StdioCollector {
            onStreamFinished: root.others = text.split("\n").filter(n => n).map(n => ({ id: "~/" + n, label: n }))
        }
    }

    Timer {
        id: watch
        interval: 4000
        repeat: true
        property int left: 0
        onRunningChanged: if (running) left = 150
        onTriggered: {
            root.refresh();
            if (--left <= 0 || (root.known && !root.running && root.connected && root.last > 0)) stop();
        }
    }
}
