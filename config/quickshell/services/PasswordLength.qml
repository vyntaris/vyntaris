pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Unlock without Enter: only your password's length is kept, never the password, so the lock screen and the
// password prompt for system changes can go on once that many are typed. 0 is not known (yet).
Singleton {
    id: root

    readonly property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/vyntaris/lock-length"
    FileView { id: store; path: root.path; printErrors: false; blockLoading: true }
    property int known: parseInt(store.text()) || 0

    function remember(n) {
        if (n === known) return;
        known = n;
        Quickshell.execDetached(["sh", "-c", 'umask 077; mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", path, String(n)]);
    }
    // A wrong one at the known length (the password changed?): Enter again until it's learned anew.
    function failed(tried) { if (tried === known) remember(0); }
}
