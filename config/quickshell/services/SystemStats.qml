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
    property real diskUsed: 0
    property real diskTotal: 0
    readonly property real disk: diskTotal > 0 ? diskUsed / diskTotal : 0
    property real uptime: 0
    // The busiest graphics card, 0 to 1; -1 when none says (an Intel one doesn't, nor a sleeping one).
    property real gpu: -1

    function formatBytes(b, decimals = 1) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < units.length - 1) { b /= 1024; i++; }
        return b.toFixed(i === 0 ? 0 : decimals) + " " + units[i];
    }

    property var lastCpu: null

    readonly property bool watched: Panels.controlOpen || Panels.systemOpen
    onWatchedChanged: if (watched) {
        lastCpu = null; cpuHistory = [];
        df.running = true;
        sample();
        firstRate.restart();
    }
    function sample() {
        stat.reload();
        meminfo.reload();
        uptimeFile.reload();
        if (tempFile.path) tempFile.reload();
        if (!gpuProc.running) gpuProc.running = true;
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
    // A sleeping card isn't read, so it isn't woken. NVIDIA's second card is asked only while an app has it awake:
    // asked all the time, it wouldn't go back to sleep.
    readonly property bool askNvidia: !Gpu.present || (Gpu.awake && Gpu.users.length > 0)
    Process {
        id: gpuProc
        command: ["sh", "-c",
            'best=-1; for c in /sys/class/drm/card[0-9]*; do case "$c" in *-*) continue ;; esac; d=$(readlink -f "$c/device"); '
            + '[ "$(cat "$d/power/runtime_status" 2>/dev/null || echo active)" = active ] || continue; '
            + 'if [ -r "$d/gpu_busy_percent" ]; then b=$(cat "$d/gpu_busy_percent" 2>/dev/null); '
            + 'elif [ "$(cat "$d/vendor")" = 0x10de ] && [ "$1" = 1 ] && command -v nvidia-smi >/dev/null; then '
            + 'b=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -dc 0-9); '
            + 'else continue; fi; [ -n "$b" ] && [ "$b" -gt "$best" ] && best=$b; done; echo "$best"',
            "sh", root.askNvidia ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseInt(text);
                root.gpu = isNaN(v) || v < 0 ? -1 : Math.min(1, v / 100);
            }
        }
    }

    Component.onCompleted: df.running = true
}
