pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property string mode: ""
    property string command: ""
    property bool backingUp: false

    function run(kind, cmd) {
        if (mode) return;
        mode = kind;
        command = cmd;
        if ((kind === "shutdown" || kind === "reboot") && Config.cloudBackup.when === "shutdown") {
            backingUp = true;
            backup.running = true;
            return;
        }
        go.restart();
    }
    function skipBackup() {
        if (backingUp) Quickshell.execDetached(["vyntaris-cloud-backup", "stop"]);
    }
    Process {
        id: backup
        command: ["systemd-run", "--user", "--wait", "--collect", "--quiet", "--unit=vyntaris-cloud-backup-now",
                  "vyntaris-cloud-backup", "run", "--now"]
        onExited: { root.backingUp = false; go.restart(); }
    }

    function preview(kind) {
        mode = kind;
        command = "";
        endPreview.restart();
    }
    Timer { id: endPreview; interval: 3000; onTriggered: root.mode = "" }

    Timer {
        id: go
        interval: 1100
        onTriggered: Quickshell.execDetached(["sh", "-c",
            'touch "${XDG_RUNTIME_DIR:-/tmp}/vyntaris-leaving"; ' + root.command])
    }
    Timer {
        running: root.mode !== "" && !root.backingUp
        interval: 20000
        onTriggered: {
            Quickshell.execDetached(["sh", "-c", 'rm -f "${XDG_RUNTIME_DIR:-/tmp}/vyntaris-leaving"']);
            root.mode = "";
        }
    }
}
