pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property string lastPath: ""
    property bool shown: false

    readonly property string directory: UserDirs.pictures + "/Screenshots"

    function capture(mode) {
        if (delay.running) return;
        if (proc.running) proc.running = false;
        delay.mode = mode;
        delay.start();
    }
    Timer {
        id: delay
        property string mode
        interval: 350
        onTriggered: root.run(mode)
    }

    function run(mode) {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        const file = `${directory}/Screenshot_${stamp}.png`;
        const grab = mode === "region"
            ? `geom="$(slurp -d -b "#00000080" -s "#00000000" -c "$2" -w 2 < /dev/null)" || exit 1; sleep 0.1; grim -g "$geom" "$1"`
            : `sleep 0.25; grim "$1"`;
        proc.target = file;
        proc.command = ["sh", "-c", `mkdir -p "$(dirname "$1")" && ${grab} && wl-copy --type image/png < "$1" >/dev/null 2>&1`,
            "sh", file, String(Theme.accent) + "ff"];
        proc.running = true;
    }

    function open() {
        if (lastPath) Config.launch(["xdg-open", lastPath]);
        shown = false;
    }
    function openFolder() {
        Config.launch(["xdg-open", directory]);
        shown = false;
    }
    function rename(name) {
        name = name.trim().replace(/[\/]/g, "-");
        if (!lastPath || !name) return;
        if (!name.toLowerCase().endsWith(".png")) name += ".png";
        const target = directory + "/" + name;
        if (target === lastPath) return;
        mover.target = target;
        mover.command = ["mv", "-n", lastPath, target];
        mover.running = true;
    }

    function editShot() {
        if (!lastPath) return;
        Quickshell.execDetached(["sh", "-c", 'command -v swappy >/dev/null && swappy -f "$1" -o "$1" || xdg-open "$1"', "sh", lastPath]);
        shown = false;
    }

    function remove() {
        if (lastPath) Quickshell.execDetached(["rm", "-f", lastPath]);
        lastPath = "";
        shown = false;
    }

    Process {
        id: mover
        property string target
        onExited: code => { if (code === 0) root.lastPath = target; }
    }

    Process {
        id: proc
        property string target
        onExited: code => {
            if (code !== 0) return;
            root.lastPath = target;
            root.shown = true;
            hideTimer.restart();
        }
    }

    Timer {
        id: hideTimer
        interval: 6000
        onTriggered: root.shown = false
    }
    function dismiss() {
        hideTimer.stop();
        shown = false;
    }
    function keepOpen(hovered) {
        if (hovered) hideTimer.stop(); else hideTimer.restart();
    }
}
