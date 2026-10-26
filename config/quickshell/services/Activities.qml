pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import Qt.labs.folderlistmodel
import qs.config

Singleton {
    id: root

    property var current: null
    readonly property bool shown: current !== null

    function banner(icon, title, sub, progress, color, ms) {
        current = { icon, title, sub: sub ?? "", progress: progress ?? -1, color: color ?? Theme.accent };
        bannerTimer.interval = ms || 3500;
        bannerTimer.restart();
    }
    function dismiss() { current = null; }
    Timer { id: bannerTimer; onTriggered: root.current = null }

    function chime() {
        if (Config.theme.sounds)
            Quickshell.execDetached(["pw-play", Quickshell.shellPath("assets/sounds/chime.wav")]);
    }

    function duration(seconds) {
        if (!(seconds > 0)) return "";
        const h = Math.floor(seconds / 3600), m = Math.round(seconds % 3600 / 60);
        return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${Math.max(1, m)}m`;
    }

    property bool armed: false
    Timer { running: true; interval: 4000; onTriggered: root.armed = true }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            Battery.refresh();
            if (root.armed && Battery.available) chargeDelay.restart();
        }
    }
    Timer {
        id: chargeDelay
        interval: 900
        onTriggered: {
            const plugged = !UPower.onBattery;
            const dev = UPower.displayDevice;
            if (!dev?.ready) return;
            const pct = Battery.percent;
            const time = plugged ? root.duration(dev?.timeToFull) : root.duration(dev?.timeToEmpty);
            root.banner("battery",
                (plugged ? Tr.t("Charging") : Tr.t("On battery")),
                pct + "%" + (time ? " · " + (plugged ? "full in " : "left ") + time : ""),
                pct / 100, plugged ? Theme.accent : pct <= 20 ? Theme.warning : Theme.text, 3500);
        }
    }

    property var progress: []
    function trackProgress(n) {
        if (progress.includes(n)) return;
        progress = progress.concat([n]);
        n.closed.connect(() => { root.progress = root.progress.filter(x => x !== n); delete root.doneAt[n.id]; });
    }
    property var doneAt: ({})
    Timer {
        interval: 500
        repeat: true
        running: root.progress.length > 0
        onTriggered: {
            const now = Date.now();
            for (const n of root.progress) {
                if (Number(n.hints?.value ?? 0) < 100) { delete root.doneAt[n.id]; continue; }
                root.doneAt[n.id] = root.doneAt[n.id] ?? now;
                if (now - root.doneAt[n.id] < 1500) continue;
                root.banner("check", n.summary || n.appName, n.body || "", -1, Theme.accent, 2500);
                n.expire();
            }
        }
    }

    readonly property string downloadDir: UserDirs.download
    property var downloads: []
    property var sizes: ({})

    Process {
        id: scan
        command: ["sh", "-c",
            'cd "$1" 2>/dev/null || exit 0; '
            + 'find . -maxdepth 1 -type f \\( -name "*.part" -o -name "*.crdownload" -o -name "*.download" \\) -printf "P\\t%s\\t%f\\n"; '
            + 'find . -maxdepth 1 -type f -newermt "-15 seconds" ! -name "*.part" ! -name "*.crdownload" ! -name "*.download" -size +0 -printf "F\\t%s\\t%f\\n"',
            "sh", root.downloadDir]
        stdout: StdioCollector { onStreamFinished: root.update(text) }
    }
    FolderListModel {
        id: partials
        folder: "file://" + root.downloadDir
        nameFilters: ["*.part", "*.crdownload", "*.download"]
        showDirs: false
        showHidden: true
        onCountChanged: rescan.restart()
    }
    Timer { id: rescan; interval: 300; onTriggered: if (scan.running) restart(); else scan.running = true }
    Timer {
        interval: 1500
        repeat: true
        running: partials.count > 0
        onTriggered: if (!scan.running) scan.running = true
    }

    function size(bytes) {
        return bytes >= 1e9 ? (bytes / 1e9).toFixed(1) + " GB"
            : bytes >= 1e6 ? (bytes / 1e6).toFixed(1) + Tr.t(" MB")
            : Math.round(bytes / 1e3) + Tr.t(" kB");
    }

    function update(text) {
        const next = {}, finished = new Set(), list = [];
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f.length < 3) continue;
            const kind = f[0], file = f[2], n = Number(f[1]);
            if (kind === "F") { finished.add(file); continue; }
            if (!(n > 0)) continue;
            next[file] = n;
            const speed = Math.max(0, (n - (sizes[file] ?? n)) / 1.5);
            list.push({ file, name: file.replace(/\.(part|crdownload|download)$/, ""), bytes: n, speed });
        }
        for (const file of Object.keys(sizes)) {
            const name = file.replace(/\.(part|crdownload|download)$/, "");
            if (!(file in next) && finished.has(name))
                banner("download", Tr.t("Downloaded"), name, -1, Theme.accent, 3500);
        }
        sizes = next;
        downloads = list;
    }

    function openDownloads() { Config.launch(["xdg-open", downloadDir]); }

    property var packages: null
    readonly property bool installing: packages !== null && packages.busy
    readonly property bool removing: installing && packages.removed > 0 && packages.removed === packages.count
    readonly property bool pacmanBusy: pacmanLock.count > 0 || installing
    FolderListModel {
        id: pacmanLock
        folder: "file:///var/lib/pacman"
        nameFilters: ["db.lck"]
        showDirs: false
        showHidden: true
        onCountChanged: if (count > 0 && !root.installing) { root.packages = null; root.pollPackages(); }
    }
    Component.onCompleted: pollPackages()
    function pollPackages() {
        if (pacmanProc.running) return;
        pacmanProc.command = [Quickshell.shellPath("scripts/pacman-progress.sh"), root.packages ? String(root.packages.since) : ""];
        pacmanProc.running = true;
    }
    Timer {
        interval: 1000
        repeat: true
        running: pacmanLock.count > 0 || root.installing
        onTriggered: root.pollPackages()
    }
    Process {
        id: pacmanProc
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const f = (lines.shift() ?? "").trim().split(" ");
                if (f.length < 4) return;
                const was = root.packages;
                const now = { since: Number(f[0]), state: f[1], count: parseInt(f[2]) || 0, busy: f[3] === "1",
                              name: f[4] === "-" ? "" : f[4] ?? "", source: f[5] ?? "log", removed: parseInt(f[6]) || 0,
                              lines: lines.filter(l => l.length > 0) };
                if (now.source === "log" && was && was.since === now.since && was.source !== "log") {
                    now.source = was.source;
                    now.lines = was.lines;
                }
                if (!was && !now.busy) return;
                if (!now.busy && now.state === "running") now.state = "failed";
                root.packages = now;
                if (was?.busy && !now.busy) {
                    if (now.state === "done" && now.count > 0)
                        root.banner("check", now.removed === now.count ? Tr.t("Packages removed") : Tr.t("Packages installed"),
                                    now.count + (now.count === 1 ? Tr.t(" package") : Tr.t(" packages")), -1, Theme.accent, 3000);
                    else if (now.state === "failed")
                        root.banner("alert", Tr.t("Installation failed"), now.count > 0 ? now.count + Tr.t(" done before it stopped") : Tr.t("Nothing was changed"), -1, Theme.red, 5000);
                }
            }
        }
    }

    property string cloud: ""
    readonly property string cloudFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-cloud-backup/now"
    property bool cloudReady: false
    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1"', "sh", root.cloudFile]
        onExited: root.cloudReady = true
    }
    FileView {
        path: root.cloudReady ? root.cloudFile : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.cloudSaid(text().trim())
    }
    function cloudSaid(line) {
        const was = cloud;
        cloud = line.startsWith("done") ? "" : line;
        if (!was || cloud) return;
        if (line === "done ok")
            banner("check", Tr.t("Backed up to Google Drive"), "", -1, Theme.accent, 3000);
        else if (line === "done stopped")
            banner("stop", Tr.t("Backup stopped"), Tr.t("What was sent stays; the next backup goes on from there."), -1, Theme.overlay1, 3000);
        else if (line.startsWith("done failed"))
            banner("alert", Tr.t("The backup didn't finish"), line.slice(12), -1, Theme.red, 6000);
    }

    readonly property var items: {
        const out = [];
        if (Chrono.timerActive)
            out.push({ kind: "timer", icon: "timer", text: Chrono.formatUp(Chrono.timerLeft),
                       progress: Chrono.timerProgress, color: Theme.accent, paused: !Chrono.timerRunning });
        if (Chrono.swActive)
            out.push({ kind: "stopwatch", icon: "timer", text: Chrono.format(Chrono.swElapsed),
                       progress: -1, color: Theme.accent, paused: !Chrono.swRunning });
        for (const n of progress) {
            const v = Math.max(0, Math.min(100, Number(n.hints?.value ?? 0)));
            out.push({ kind: "progress", icon: "refresh", text: Math.round(v) + "%", title: n.summary || n.appName,
                       progress: v / 100, color: Theme.accent, paused: false });
        }
        for (const d of downloads)
            out.push({ kind: "download", icon: "download", text: d.speed > 0 ? size(d.speed) + "/s" : size(d.bytes),
                       progress: -1, color: Theme.accent, paused: false });
        if (cloud === "connecting")
            out.push({ kind: "backup", icon: "cloud", text: Tr.t("Sign-in"), title: "Google", progress: -1, color: Theme.accent, paused: false });
        else if (cloud.startsWith("backing-up")) {
            const f = cloud.split(" "), pct = Math.max(0, Math.min(100, parseInt(f[1]) || 0));
            out.push({ kind: "backup", icon: "cloud", text: f.slice(2).join(" ") + " · " + pct + "%", title: Tr.t("Backing up"),
                       progress: pct / 100, color: Theme.accent, paused: false });
        }
        if (installing)
            out.push({ kind: "packages", icon: "package-update", text: packages.count > 0 ? packages.count + " · " + packages.name : root.removing ? Tr.t("Removing") : Tr.t("Installing"),
                       progress: -1, color: Theme.accent, paused: false });
        return out;
    }
}
