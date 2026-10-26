pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property var list: []

    function refresh() { proc.running = true; }

    readonly property var keyNames: ({
        "space": Tr.t("Space"), "Return": Tr.t("Enter"), "Backspace": Tr.t("Backspace"), "Tab": Tr.t("Tab"), "Delete": Tr.t("Delete"),
        "Print": Tr.t("PrtSc"), "left": "←", "right": "→", "up": "↑", "down": "↓", "Escape": Tr.t("Esc"),
        "period": ".", "grave": "`", "bracketleft": "[", "bracketright": "]", "equal": "=", "minus": "−",
        "mouse:272": Tr.t("Left drag"), "mouse:273": Tr.t("Right drag"), "mouse_down": Tr.t("Scroll ↓"), "mouse_up": Tr.t("Scroll ↑"),
        "Super_L": Tr.t("SUPER (tap)"), "switch:on:Lid Switch": Tr.t("Lid"),
        "XF86AudioRaiseVolume": Tr.t("Volume +"), "XF86AudioLowerVolume": Tr.t("Volume −"), "XF86AudioMute": Tr.t("Mute"),
        "XF86AudioMicMute": Tr.t("Mic mute"), "XF86MonBrightnessUp": Tr.t("Brightness +"), "XF86MonBrightnessDown": Tr.t("Brightness −"),
        "XF86AudioPlay": Tr.t("Play"), "XF86AudioPause": Tr.t("Pause"), "XF86AudioNext": Tr.t("Next"), "XF86AudioPrev": Tr.t("Previous"),
    })
    function keyName(k) { return keyNames[k] ?? k.replace(/^XF86/, ""); }
    readonly property var groups: [
        { id: "apps", label: Tr.t("Apps"), icon: "apps" },
        { id: "desktop", label: Tr.t("Desktop"), icon: "vyntaris" },
        { id: "windows", label: Tr.t("Windows"), icon: "windows" },
        { id: "workspaces", label: Tr.t("Workspaces"), icon: "monitor" },
        { id: "screenshots", label: Tr.t("Screenshots"), icon: "camera" },
        { id: "hardware", label: Tr.t("Hardware keys"), icon: "sliders" },
    ]
    function group(key, what) {
        if (/^(Screenshot|Record)/.test(what)) return "screenshots";
        if (/^(XF86|switch:)/.test(key) || key === "Help") return "hardware";
        if (/^(Terminal|Files|Browser|Code editor|Task manager|Pick a color)/.test(what)) return "apps";
        if (/workspace|scratchpad/i.test(what)) return "workspaces";
        if (/window|^(Fullscreen|Float|Pin|Focus|Zoom)|split|tab in group/i.test(what)) return "windows";
        return "desktop";
    }
    function mods(m) {
        const out = [];
        if (m & 64) out.push("SUPER");
        if (m & 4) out.push("CTRL");
        if (m & 8) out.push("ALT");
        if (m & 1) out.push("SHIFT");
        return out;
    }

    Process {
        id: proc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const seen = new Set();
                    root.list = JSON.parse(text).filter(b => b.description).map(b => {
                        const keys = b.key === "Super_L" ? [root.keyName(b.key)] : root.mods(b.modmask).concat([root.keyName(b.key)]);
                        return { keys, what: b.description, group: root.group(b.key, b.description) };
                    }).filter(b => {
                        const id = b.keys.join("+") + b.what;
                        if (seen.has(id)) return false;
                        seen.add(id);
                        return true;
                    });
                } catch (e) { root.list = []; }
            }
        }
    }
}
