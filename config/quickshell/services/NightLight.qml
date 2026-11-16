pragma Singleton
import Quickshell
import QtQuick
import qs.config

Singleton {
    id: root

    property bool override: false
    property bool overrideValue: false
    readonly property bool scheduled: Config.nightLight.automatic && inWindow(clock.date)
    readonly property bool active: override ? overrideValue : scheduled

    function toggle() {
        override = true;
        overrideValue = !active;
    }

    function inWindow(now) {
        const mins = s => { const t = (s || "0:0").split(":").map(Number); return t[0] * 60 + (t[1] || 0); };
        const n = now.getHours() * 60 + now.getMinutes();
        const a = mins(Config.nightLight.start), b = mins(Config.nightLight.end);
        return a <= b ? n >= a && n < b : n >= a || n < b;
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    onScheduledChanged: override = false

    // Restored once settings are in, and only while the schedule is where it was.
    property bool restored: false
    function save() {
        if (restored) SessionState.set("nightLight", { override, overrideValue, scheduled });
    }
    onOverrideChanged: save()
    onOverrideValueChanged: save()

    onActiveChanged: apply()
    Component.onCompleted: startDelay.start()
    Timer {
        id: startDelay
        interval: 1500
        onTriggered: {
            const s = SessionState.get("nightLight");
            if (s?.override && s.scheduled === root.scheduled) {
                root.overrideValue = !!s.overrideValue;
                root.override = true;
            }
            root.restored = true;
            root.apply();
        }
    }

    function apply() {
        const cmd = active
            ? `hyprctl hyprsunset temperature ${Config.nightLight.temperature}`
            : "hyprctl hyprsunset identity";
        Quickshell.execDetached(["sh", "-c",
            `command -v hyprsunset >/dev/null || exit 0; `
            + `pidof hyprsunset >/dev/null || { systemctl --user start hyprsunset.service 2>/dev/null || setsid -f hyprsunset >/dev/null 2>&1; sleep 0.5; }; ${cmd}`]);
    }
}
