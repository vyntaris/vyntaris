pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property bool guarded: false
    property string reason: ""
    property string point: ""
    property bool pending: false
    property var rollback: null
    readonly property string pointDate: when(point)

    function when(name) {
        const m = /^(\d{4})-(\d\d)-(\d\d)_(\d\d)-(\d\d)/.exec(name ?? "");
        if (!m) return "";
        return Qt.formatDateTime(new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]), "d MMM yyyy, hh:mm");
    }

    FileView {
        path: "/var/lib/vyntaris/update-guard.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let s = {};
            try { s = JSON.parse(text()); } catch (e) { s = {}; }
            root.guarded = s.protected === true;
            root.reason = s.reason ?? "";
            root.point = s.point ?? "";
            root.pending = s.pending === true;
            root.rollback = s.rollback ?? null;
        }
        onLoadFailed: { root.guarded = false; root.reason = "not set up yet"; root.point = ""; root.rollback = null; }
    }

    function undo() {
        if (!point || undoing.running) return;
        undoing.running = true;
    }
    Process {
        id: undoing
        command: ["pkexec", "/usr/lib/vyntaris/update-guard", "undo"]
        onExited: code => {
            if (code === 0) Leaving.run("reboot", Config.power.reboot);
            else if (code !== 126 && code !== 127)
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Safe updates"), "-i", "dialog-warning",
                    Tr.t("The update can't be undone"), Tr.t("Nothing was changed.")]);
        }
    }

    readonly property string seenFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/vyntaris/rollback-seen"
    FileView {
        id: seen
        path: root.seenFile
        printErrors: false
        blockLoading: true
    }
    onRollbackChanged: {
        const at = rollback?.at ?? "";
        if (!at) return;
        seen.reload();
        if (seen.text().trim() === at) return;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", seenFile, at]);
        Quickshell.execDetached(["notify-send", "-a", Tr.t("Safe updates"), "-i", "edit-undo", "-u", "critical",
            Tr.t("The last update was undone"),
            Tr.t("Vyntaris couldn't start after it, so it went back to how it was on ") + when(rollback.snapshot.split("/")[2] ?? "")
            + ". Your files weren't touched. The update will be offered again once newer versions are out."]);
    }
}
