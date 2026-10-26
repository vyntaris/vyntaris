pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.config

Singleton {
    id: root

    property var waiting: []
    property bool told: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitoraddedv2") {
                const name = event.data.split(",")[1] ?? "";
                Hyprland.refreshMonitors();
                announce.name = name;
                announce.restart();
            } else if (event.name === "monitorremoved") {
                Activities.banner("monitor", Tr.t("Display disconnected"), event.data, -1, Theme.overlay1, 2500);
            }
        }
    }
    Timer {
        id: announce
        property string name
        interval: 600
        onTriggered: {
            const m = Hyprland.monitors.values.find(m => m.name === name);
            const o = m?.lastIpcObject ?? {};
            const size = o.width ? `${o.width}×${o.height}` : "";
            Activities.banner("monitor", Tr.t("Display connected"), [name, size].filter(s => s).join(" · "), -1, Theme.accent, 3000);
        }
    }

    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=drm"]
        stdout: SplitParser { onRead: settle.restart() }
    }
    Timer { id: settle; interval: 1500; onTriggered: { Hyprland.refreshMonitors(); check.running = true; } }

    Process {
        id: check
        command: ["sh", "-c",
            'for c in /sys/class/drm/card[0-9]*-*; do card="${c##*/}"; card="${card%%-*}"; '
            + '[ "$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)" = 0x10de ] || continue; '
            + '[ "$(cat "$c/status" 2>/dev/null)" = connected ] && echo "${c##*/$card-}"; done; true']
        stdout: StdioCollector {
            onStreamFinished: {
                const shown = Hyprland.monitors.values.map(m => m.name);
                root.waiting = text.split("\n").filter(n => n && !shown.includes(n));
            }
        }
    }

    onWaitingChanged: {
        if (waiting.length === 0) { told = false; return; }
        if (told) return;
        told = true;
        ask.running = true;
    }
    Process {
        id: ask
        command: ["notify-send", "-a", "Displays", "-i", "video-display", "-A", "logout=Log out",
            Tr.t("Log out to use ") + root.waiting.join(", "),
            Tr.t("That port is on the NVIDIA card, off to save battery until the next login.")]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "logout") Leaving.run("logout", Config.power.logout)
        }
    }
}
