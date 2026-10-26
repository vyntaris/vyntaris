pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string mode: "off"
    readonly property bool active: mode !== "off"
    readonly property bool inhibitDisplay: mode === "display"

    property int minutes: 0
    property date until
    property real remaining: 0

    readonly property string icon: mode === "display" ? "coffee"
        : mode === "system" ? "coffee-moon" : "cup"

    function set(newMode, newMinutes) {
        mode = newMode;
        if (newMinutes !== undefined) minutes = newMinutes;
        restartTimer();
    }
    function setMinutes(m) {
        minutes = m;
        restartTimer();
    }
    function toggle() {
        set(active ? "off" : "display");
    }

    function restartTimer() {
        if (active && minutes > 0) {
            until = new Date(Date.now() + minutes * 60000);
            remaining = minutes * 60;
        } else {
            remaining = 0;
        }
    }

    function format(sec) {
        const h = Math.floor(sec / 3600), m = Math.ceil(sec % 3600 / 60);
        return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
    }

    Timer {
        running: root.active && root.minutes > 0
        interval: 1000
        repeat: true
        onTriggered: {
            root.remaining = Math.max(0, (root.until - Date.now()) / 1000);
            if (root.remaining <= 0) root.set("off");
        }
    }

    onModeChanged: {
        inhibitor.running = false;
        restartInhibitor.restart();
    }
    Timer {
        id: restartInhibitor
        interval: 150
        onTriggered: inhibitor.running = root.active
    }

    Process {
        id: inhibitor
        running: false
        command: ["systemd-inhibit", `--what=${root.inhibitDisplay ? "idle:sleep" : "sleep"}`,
                  "--who=Quickshell", "--why=Keep awake", "--mode=block", "sleep", "infinity"]
    }
}
