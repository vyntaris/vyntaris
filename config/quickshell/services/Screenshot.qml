pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

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

    function openFolder() {
        Config.launch(["xdg-open", directory]);
    }

    Process {
        id: proc
        property string target
        onExited: code => { if (code === 0) Osd.show("screenshot"); }
    }
}
