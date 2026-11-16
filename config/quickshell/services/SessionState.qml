pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What the shell was doing (keep awake, a timer, game mode...), kept across a reload or restart.
// It lives in the runtime dir, so it's gone at logout.
Singleton {
    id: root

    property var data: null

    function get(key) {
        if (data === null) {
            try { data = JSON.parse(file.text()) || {}; } catch (e) { data = {}; }
        }
        return data[key];
    }
    function set(key, value) {
        get(key);
        data[key] = value;
        file.setText(JSON.stringify(data));
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-shell-state.json"
        blockLoading: true
        printErrors: false
    }
}
