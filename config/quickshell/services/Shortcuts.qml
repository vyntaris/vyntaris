pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.config

Singleton {
    id: root

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
        if (/^(Screenshot|Record|Copy text)/.test(what)) return "screenshots";
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
    readonly property var modOrder: ["SUPER", "CTRL", "ALT", "SHIFT"]
    readonly property var modAliases: ({ SUPER: "SUPER", MOD4: "SUPER", WIN: "SUPER", META: "SUPER", CTRL: "CTRL", CONTROL: "CTRL",
                                         ALT: "ALT", MOD1: "ALT", SHIFT: "SHIFT" })
    // "SUPER + shift + e" as { mods: ["SUPER", "SHIFT"], key: "e" }, the same however it was written.
    function parse(combo) {
        const parts = String(combo).split("+").map(p => p.trim()).filter(p => p);
        const mods = [];
        let key = "";
        for (const p of parts) {
            const m = modAliases[p.toUpperCase()];
            if (m && !mods.includes(m)) mods.push(m);
            else if (!m) key = p;
        }
        return { mods: modOrder.filter(m => mods.includes(m)), key };
    }
    function canonical(combo) { const c = parse(combo); return c.mods.concat([c.key.toLowerCase()]).join("+"); }
    function display(combo) {
        if (combo === "SUPER + Super_L") return [keyName("Super_L")];
        const c = parse(combo);
        return c.mods.concat([keyName(c.key.length === 1 ? c.key.toUpperCase() : c.key)]);
    }

    // What hyprland.lua bound and how, from what it writes down each time it loads.
    property var written: []
    property var bound: []
    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-shortcuts.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.written = JSON.parse(text()); } catch (e) { root.written = []; } root.refresh(); }
        onLoadFailed: root.written = []
    }
    readonly property var list: {
        const seen = new Set(), out = [];
        for (const w of written) {
            if (!w.description) continue;
            const off = w.keys === "";
            const id = (off ? "off:" + w.default : canonical(w.keys)) + w.description;
            if (seen.has(id)) continue;
            seen.add(id);
            out.push({ keys: off ? [] : display(w.keys), combo: w.keys, what: w.description, group: group(parse(w.default).key, w.description),
                       default: w.default, editable: w.editable, changed: w.keys !== w.default });
        }
        // Bound elsewhere (~/.config/hypr/user.lua): shown, not changed here.
        const ours = new Set(written.map(w => w.description)), keys = new Set(written.filter(w => w.keys).map(w => canonical(w.keys)));
        for (const b of bound) {
            if (ours.has(b.what) || keys.has(canonical(b.combo)) || seen.has(canonical(b.combo) + b.what)) continue;
            seen.add(canonical(b.combo) + b.what);
            out.push(b);
        }
        return out;
    }
    // What else these keys do, now; null when nothing.
    function takenBy(combo, except) {
        const c = canonical(combo);
        return list.find(b => b.combo && b.default !== except && canonical(b.combo) === c) ?? null;
    }

    // Keys for a shortcut: "" turns it off, its own keys put it back. Keys another one has are refused.
    function set(entry, combo) {
        if (combo && takenBy(combo, entry.default)) return false;
        const all = Object.assign({}, Config.shortcuts ?? {});
        if (canonical(combo || "") === canonical(entry.default)) delete all[entry.default];
        else all[entry.default] = combo;
        Config.shortcuts = all;
        Config.save();
        return true;
    }

    // Recording: Hyprland's own shortcuts all rest meanwhile, so the keys reach the window.
    property bool recording: false
    function record(on) {
        if (recording === on) return;
        recording = on;
        Hyprland.dispatch(on ? 'hl.dsp.submap("vyntaris-record")' : 'hl.dsp.submap("reset")');
        if (on) giveUp.restart(); else giveUp.stop();
        // A watch of its own: should this process die while recording (a crash, killed), the shortcuts come back
        // all the same, as soon as it's gone or after 20 s.
        if (on) {
            self.reload();
            const pid = parseInt(self.text()) || 0;
            Quickshell.execDetached(["sh", "-c",
                'i=0; while [ "$i" -lt 40 ] && kill -0 "$1" 2>/dev/null; do sleep 0.5; i=$((i + 1)); done; '
                + '[ "$(hyprctl submap 2>/dev/null)" = vyntaris-record ] && hyprctl dispatch \'hl.dsp.submap("reset")\' >/dev/null',
                "sh", String(pid)]);
        }
    }
    FileView { id: self; path: "/proc/self/stat"; blockLoading: true; printErrors: false }
    // Should nothing come (or the window lose its keys), the shortcuts don't stay off.
    Timer { id: giveUp; interval: 15000; onTriggered: root.record(false) }
    Component.onDestruction: if (recording) Hyprland.dispatch('hl.dsp.submap("reset")')

    readonly property var shifted: ({
        [Qt.Key_Exclam]: "1", [Qt.Key_At]: "2", [Qt.Key_NumberSign]: "3", [Qt.Key_Dollar]: "4", [Qt.Key_Percent]: "5",
        [Qt.Key_AsciiCircum]: "6", [Qt.Key_Ampersand]: "7", [Qt.Key_Asterisk]: "8", [Qt.Key_ParenLeft]: "9", [Qt.Key_ParenRight]: "0",
        [Qt.Key_Underscore]: "minus", [Qt.Key_Plus]: "equal", [Qt.Key_AsciiTilde]: "grave", [Qt.Key_BraceLeft]: "bracketleft",
        [Qt.Key_BraceRight]: "bracketright", [Qt.Key_Colon]: "semicolon", [Qt.Key_QuoteDbl]: "apostrophe", [Qt.Key_Less]: "comma",
        [Qt.Key_Greater]: "period", [Qt.Key_Question]: "slash", [Qt.Key_Bar]: "backslash",
    })
    readonly property var named: ({
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Space]: "space", [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab",
        [Qt.Key_Escape]: "Escape", [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next",
        [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Print]: "Print",
        [Qt.Key_Period]: "period", [Qt.Key_Comma]: "comma", [Qt.Key_Minus]: "minus", [Qt.Key_Equal]: "equal",
        [Qt.Key_QuoteLeft]: "grave", [Qt.Key_BracketLeft]: "bracketleft", [Qt.Key_BracketRight]: "bracketright",
        [Qt.Key_Slash]: "slash", [Qt.Key_Backslash]: "backslash", [Qt.Key_Semicolon]: "semicolon", [Qt.Key_Apostrophe]: "apostrophe",
    })
    // A key press as Hyprland writes the keys ("SUPER + SHIFT + E"); "" for a modifier on its own.
    function comboOf(event) {
        const k = event.key;
        if ([Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift, Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R].includes(k)) return "";
        let key = "";
        if (k >= Qt.Key_A && k <= Qt.Key_Z) key = String.fromCharCode(k);
        else if (k >= Qt.Key_0 && k <= Qt.Key_9) key = String.fromCharCode(k);
        else if (k >= Qt.Key_F1 && k <= Qt.Key_F24) key = "F" + (k - Qt.Key_F1 + 1);
        else key = named[k] ?? shifted[k] ?? "";
        if (!key) return "";
        const m = event.modifiers, mods = [];
        if (m & Qt.MetaModifier) mods.push("SUPER");
        if (m & Qt.ControlModifier) mods.push("CTRL");
        if (m & Qt.AltModifier) mods.push("ALT");
        if (m & Qt.ShiftModifier) mods.push("SHIFT");
        return mods.concat([key]).join(" + ");
    }

    Process {
        id: proc
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.bound = JSON.parse(text).filter(b => b.description && (b.submap ?? "") === "").map(b => {
                        const combo = b.key === "Super_L" ? "SUPER + Super_L" : root.mods(b.modmask).concat([b.key]).join(" + ");
                        return { keys: root.display(combo), combo, what: b.description, group: root.group(b.key, b.description), editable: false, changed: false };
                    });
                } catch (e) { root.bound = []; }
            }
        }
    }
}
