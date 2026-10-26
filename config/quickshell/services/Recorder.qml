pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property bool recording: proc.running
    property int seconds: 0
    property string lastPath: ""

    readonly property string directory: UserDirs.videos + "/Recordings"

    function toggle(mode) {
        if (recording) stop();
        else if (counting || pick.running) cancel();
        else start(mode || "region");
    }

    property int countdown: 0
    readonly property bool counting: countdown > 0
    property string geometry: ""

    function start(mode) {
        if (recording || delay.running || counting || pick.running) return;
        geometry = "";
        if (mode === "region") pick.running = true;
        else beginCountdown();
    }

    function cancel() {
        tick.stop();
        countdown = 0;
        if (pick.running) pick.signal(15);
    }

    Process {
        id: pick
        command: ["sh", "-c", 'slurp -d -b "#00000080" -s "#00000000" -c "$1" -w 2 < /dev/null', "sh", String(Theme.red) + "ff"]
        stdout: StdioCollector { id: picked }
        onExited: code => {
            if (code !== 0 || !picked.text.trim()) return;
            root.geometry = picked.text.trim();
            root.beginCountdown();
        }
    }

    function beginCountdown() {
        const n = Config.live.countdown;
        if (n <= 0) { delay.start(); return; }
        countdown = n;
        tick.restart();
    }
    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--;
            if (root.countdown <= 0) { stop(); delay.start(); }
        }
    }
    Timer {
        id: delay
        interval: 450
        onTriggered: root.run()
    }

    function run() {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        const file = `${directory}/Recording_${stamp}.mp4`;
        const args = geometry ? ["-g", geometry] : [];
        proc.target = file;
        proc.command = ["sh", "-c",
            `mkdir -p "$(dirname "$1")"; out="$1"; shift; `
            + `mon="$(pactl get-default-sink 2>/dev/null).monitor"; `
            + `exec wf-recorder "$@" --audio="$mon" -f "$out" < /dev/null`,
            "sh", file].concat(args);
        seconds = 0;
        proc.running = true;
    }

    function stop() {
        if (proc.running) proc.signal(2);
    }

    function open() { if (lastPath) Config.launch(["xdg-open", lastPath]); }

    Process {
        id: proc
        property string target
        onExited: code => {
            if (code === 0 || code === 130 || code === 2) {
                root.lastPath = target;
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Screen recording"), "-i", "video-x-generic",
                    Tr.t("Recording saved"), target.split("/").pop()]);
            }
        }
    }
    Timer {
        running: root.recording
        interval: 1000
        repeat: true
        onTriggered: root.seconds++
    }

    function format(s) {
        const m = Math.floor(s / 60);
        return m + ":" + String(s % 60).padStart(2, "0");
    }
}
