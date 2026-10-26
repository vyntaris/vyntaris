pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string device: ""
    readonly property bool available: device !== "" && max > 0
    property int max: 0
    property int current: 0
    readonly property real value: available ? current / max : 0

    signal changed()

    function set(fraction) {
        if (!available) return;
        current = Math.round(Math.max(0.01, Math.min(1, fraction)) * max);
        Quickshell.execDetached(["busctl", "call", "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session",
            "SetBrightness", "ssu", "backlight", device, String(current)]);
        changed();
    }

    function step(delta) {
        set(value + delta);
    }

    property real beforeDim: -1
    function dim() {
        if (!available || beforeDim >= 0) return;
        beforeDim = value;
        set(Math.min(value, 0.1));
    }
    function restore() {
        if (beforeDim < 0) return;
        const v = beforeDim;
        beforeDim = -1;
        set(v);
    }

    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    FileView {
        path: root.device ? `/sys/class/backlight/${root.device}/max_brightness` : ""
        onLoaded: root.max = parseInt(text()) || 0
    }

    FileView {
        id: currentFile
        path: root.device ? `/sys/class/backlight/${root.device}/brightness` : ""
        onLoaded: root.current = parseInt(text()) || 0
    }
    function refresh() { if (available) currentFile.reload(); }
    Connections {
        target: Panels
        function onControlOpenChanged() { if (Panels.controlOpen) root.refresh(); }
    }
}
