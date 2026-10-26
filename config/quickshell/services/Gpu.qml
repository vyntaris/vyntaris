pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property bool enabled: Config.bar.gpu
    property string device: ""
    property string renderNode: ""
    readonly property bool present: device !== ""
    property bool awake: false
    property var users: []

    Process {
        running: true
        command: ["sh", "-c",
            'n=0; nv=""; for d in /sys/bus/pci/devices/*; do case "$(cat "$d/class")" in 0x03*) n=$((n + 1)); '
            + '[ "$(cat "$d/vendor")" = 0x10de ] && nv=$d ;; esac; done; [ "$n" -ge 2 ] && [ -n "$nv" ] || exit 0; '
            + 'r=""; for x in /sys/class/drm/renderD*; do [ "$(readlink -f "$x/device")" = "$(readlink -f "$nv")" ] && r=/dev/dri/${x##*/}; done; '
            + 'echo "$nv $r"']
        stdout: StdioCollector {
            onStreamFinished: {
                const [d, r] = text.trim().split(" ");
                root.device = d ?? "";
                root.renderNode = r ?? "";
            }
        }
    }

    FileView {
        id: status
        path: root.present && root.enabled ? root.device + "/power/runtime_status" : ""
        onLoaded: root.awake = text().trim() === "active"
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.present && root.enabled
        onTriggered: status.reload()
    }

    Process {
        id: scan
        command: ["sh", "-c",
            'find /proc/[0-9]*/fd -maxdepth 1 \\( -lname "/dev/nvidia*" -o -lname "$1" \\) 2>/dev/null '
            + '| cut -d/ -f3 | sort -u | while read -r p; do n=$(cat "/proc/$p/comm" 2>/dev/null); '
            + '[ ${#n} -ge 15 ] && n=$(basename "$(readlink "/proc/$p/exe")" 2>/dev/null); printf "%s %s\\n" "$p" "$n"; done',
            "sh", root.renderNode || "/nonexistent"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.users = text.split("\n").map(s => s.trim()).filter(s => s)
                    .map(s => ({ pid: Number(s.split(" ")[0]), app: s.slice(s.indexOf(" ") + 1) }))
                    .filter(u => u.app && !/^(nvidia-persistenced|nvidia-powerd|Xwayland|Hyprland)$/.test(u.app))
                    .filter((u, i, a) => a.findIndex(v => v.app === u.app) === i);
            }
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: root.awake
        triggeredOnStart: true
        onTriggered: if (!scan.running) scan.running = true
    }
    onAwakeChanged: if (!awake) users = []

    function close(u) {
        if (u.pid > 1) Quickshell.execDetached(["kill", "-TERM", String(u.pid)]);
    }
}
