import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    property string device: ""
    property bool active: false
    property bool wired: false

    property real down: -1
    property real up: -1
    property real ping: -1
    property string rate: ""
    property string band: ""
    property string address: ""
    property var last: null
    property bool ready: false
    property bool pinged: false

    function speed(bytes) {
        if (bytes < 0) return "–";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s";
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB/s";
        return Math.round(bytes) + " B/s";
    }

    // The counters are read straight from /sys: one now and one a moment later, so the speeds show at once
    // instead of after two rounds of the slow nmcli and ping below.
    function count() {
        rxFile.reload();
        txFile.reload();
        const rx = Number(rxFile.text()), tx = Number(txFile.text()), at = Date.now();
        if (!(rx >= 0 && tx >= 0) || rxFile.text() === "") return;
        if (last && at > last.at) {
            const seconds = (at - last.at) / 1000;
            down = Math.max(0, rx - last.rx) / seconds;
            up = Math.max(0, tx - last.tx) / seconds;
        }
        last = { rx, tx, at };
    }

    function parse(text) {
        ready = true;
        const field = key => (text.split("\n").find(l => l.startsWith(key + "=")) ?? "").slice(key.length + 1).trim();
        const [freq, bitrate] = field("l").split(":");
        const mhz = parseInt(freq);
        band = !(mhz > 0) ? "" : mhz >= 5925 ? "6 GHz" : mhz >= 5000 ? "5 GHz" : "2.4 GHz";
        rate = (bitrate ?? "").replace("Mbit/s", "Mb/s");
        address = field("a").split("|")[0].split("/")[0].trim();
    }

    onActiveChanged: if (!active) { last = null; ready = false; pinged = false; down = -1; up = -1; ping = -1; }

    readonly property bool running: active && device !== ""
    onDeviceChanged: { last = null; down = -1; up = -1; }
    onRunningChanged: if (running) { count(); secondCount.restart(); }
    FileView { id: rxFile; path: root.device ? `/sys/class/net/${root.device}/statistics/rx_bytes` : ""; blockLoading: true; printErrors: false }
    FileView { id: txFile; path: root.device ? `/sys/class/net/${root.device}/statistics/tx_bytes` : ""; blockLoading: true; printErrors: false }
    Timer { id: secondCount; interval: 300; onTriggered: root.count() }
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.count()
    }

    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.running
        onTriggered: {
            if (!read.running) read.running = true;
            if (!pinger.running) pinger.running = true;
        }
    }

    Process {
        id: read
        command: ["sh", "-c",
            'if [ "$2" = wired ]; then read s < "/sys/class/net/$1/speed" 2>/dev/null; [ "${s:-0}" -gt 0 ] 2>/dev/null && echo "l=:$s Mb/s"; '
            + 'else echo "l=$(nmcli -g IN-USE,FREQ,RATE dev wifi list ifname "$1" --rescan no 2>/dev/null | sed -n "s/^\\*://p" | head -n1)"; fi; '
            + 'echo "a=$(nmcli -g IP4.ADDRESS dev show "$1" 2>/dev/null)"',
            "sh", root.device, root.wired ? "wired" : "wifi"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    // on its own, so its second of waiting for an answer holds up nothing else
    Process {
        id: pinger
        command: ["sh", "-c", 'ping -n -c1 -W1 1.1.1.1 2>/dev/null | sed -n "s/.*time=\\([0-9.]*\\).*/\\1/p"']
        stdout: StdioCollector {
            onStreamFinished: {
                const ms = parseFloat(text);
                root.ping = ms >= 0 ? ms : -1;
                root.pinged = true;
            }
        }
    }
}
