pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property bool locked: false
    property bool preview: false
    signal woke()
    Timer { running: root.preview; interval: 15000; onTriggered: root.preview = false }
    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/shell-locked"

    function lock() {
        if (locked) return;
        Quickshell.execDetached(["touch", marker]);
        locked = true;
    }
    // The right password: the lock screen plays its way out first (it ends on the sharp wallpaper, as the desktop
    // looks), then the session unlocks. The compositor shows nothing behind a lock, so it can't fade into it.
    property bool opening: false
    function unlocked() {
        if (!locked || opening) return;
        opening = true;
        openTimer.interval = Theme.duration(650);
        openTimer.restart();
    }
    Timer {
        id: openTimer
        onTriggered: {
            Quickshell.execDetached(["rm", "-f", root.marker]);
            root.opening = false;
            root.locked = false;
        }
    }

    Process {
        running: true
        command: ["test", "-e", root.marker]
        onExited: code => { if (code === 0) root.locked = true; }
    }
}
