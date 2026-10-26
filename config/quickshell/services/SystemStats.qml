pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property int interval: 2000

    property real cpu: 0
    property var cpuHistory: []
    property real memUsed: 0
    property real memTotal: 0
    readonly property real memory: memTotal > 0 ? memUsed / memTotal : 0
    property real temperature: -1
    property real rxRate: 0
    property real txRate: 0
    property real diskUsed: 0
    property real diskTotal: 0
    readonly property real disk: diskTotal > 0 ? diskUsed / diskTotal : 0
    property real uptime: 0

    function formatBytes(b, decimals = 1) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
        return b.toFixed(i === 0 ? 0 : decimals) + " " + units[i];
    }

    property var lastCpu: null
    property var lastNet: null

    readonly property bool watched: Panels.controlOpen || Panels.systemOpen
    onWatchedChanged: if (watched) {
        lastCpu = null; lastNet = null; cpuHistory = [];
        df.running = true;
        sample();
        firstRate.restart();
    }
    function sample() {
        stat.reload();
        meminfo.reload();
        netdev.reload();
        uptimeFile.reload();
        if (tempFile.path) tempFile.reload();
    }
    Timer { id: firstRate; interval: 500; onTriggered: root.sample() }
    Timer {
        interval: root.interval
        running: root.watched
        repeat: true
        onTriggered: root.sample()
    }

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const f = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] ?? 0);
            const total = f.slice(0, 8).reduce((a, b) => a + b, 0);
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total;
                root.cpu = dt > 0 ? Math.max(0, Math.min(1, 1 - (idle - root.lastCpu.idle) / dt)) : 0;
                root.cpuHistory = root.cpuHistory.concat([root.cpu]).slice(-40);
            }
            root.lastCpu = { idle, total };
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const kb = key => parseInt((text().match(new RegExp("^" + key + ":\\s+(\\d+)", "m")) ?? [])[1] ?? 0) * 1024;
            root.memTotal = kb("MemTotal");
            root.memUsed = root.memTotal - kb("MemAvailable");
        }
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^([^:]+):\s*(.*)$/);
                if (!m || m[1] === "lo") continue;
                const f = m[2].split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now();
            if (root.lastNet) {
                const dt = (now - root.lastNet.time) / 1000;
                root.rxRate = dt > 0 ? Math.max(0, (rx - root.lastNet.rx) / dt) : 0;
                root.txRate = dt > 0 ? Math.max(0, (tx - root.lastNet.tx) / dt) : 0;
            }
            root.lastNet = { rx, tx, time: now };
        }
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptime = parseFloat(text()) || 0
    }

    FileView {
        id: tempFile
        path: ""
        onLoaded: {
            const v = parseInt(text());
            root.temperature = isNaN(v) ? -1 : v / 1000;
        }
    }
    Process {
        running: true
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do case \"$(cat $h/name 2>/dev/null)\" in " +
            "coretemp|k10temp|zenpower) echo $h/temp1_input; exit;; esac; done; " +
            "[ -e /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp"]
        stdout: StdioCollector {
            onStreamFinished: tempFile.path = text.trim()
        }
    }

    Process {
        id: df
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[1]?.trim().split(/\s+/).map(Number) ?? [];
                root.diskTotal = f[0] ?? 0;
                root.diskUsed = f[1] ?? 0;
            }
        }
    }
    Component.onCompleted: df.running = true
}
