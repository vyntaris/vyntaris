pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The Wi-Fi hotspot (scripts/hotspot.sh): this computer's internet shared over its Wi-Fi card.
Singleton {
    id: root

    readonly property string tool: Quickshell.shellPath("scripts/hotspot.sh")
    property bool active: false
    property bool busy: false
    property bool failed: false
    property string ssid: ""
    property string password: ""
    property int clients: 0
    property bool hasCard: true
    // The internet comes over the Wi-Fi card itself: turning this on drops it.
    property bool viaWifi: false
    property bool otherInternet: false
    // The QR code phones scan to join: rows of "1" and "0".
    property var qr: []

    function refresh() { statusProc.running = false; statusProc.running = true; }
    function toggle() { set(!active); }
    function set(on) {
        if (busy) return;
        busy = true;
        failed = false;
        switchProc.command = [tool, on ? "on" : "off"];
        switchProc.running = true;
    }
    function change(name, pass) {
        if (busy) return;
        busy = true;
        failed = false;
        changeProc.input = name + "\n" + pass;
        changeProc.running = true;
    }

    Process {
        id: statusProc
        command: [root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s;
                try { s = JSON.parse(text); } catch (e) { return; }
                root.hasCard = !!s.device;
                root.active = s.active;
                root.ssid = s.ssid;
                root.password = s.password;
                root.clients = s.clients;
                root.viaWifi = s.viaWifi;
                root.otherInternet = s.otherInternet;
                root.makeQr();
            }
        }
    }
    Process {
        id: switchProc
        onExited: code => { root.busy = false; root.failed = code !== 0; root.refresh(); }
    }
    Process {
        id: changeProc
        property string input: ""
        command: [root.tool, "set"]
        stdinEnabled: true
        onStarted: { write(input + "\n"); input = ""; stdinEnabled = false; }
        onExited: code => { changeProc.stdinEnabled = true; root.busy = false; root.failed = code !== 0; root.refresh(); }
    }

    // WIFI:T:WPA;S:name;P:password;; with \ ; , : " escaped, as phones' cameras read it.
    function makeQr() {
        if (!ssid || !password) { qr = []; return; }
        const esc = t => t.replace(/([\\;,:"])/g, "\\$1");
        qrProc.command = ["qrencode", "-t", "ASCII", "-m", "0", "-l", "M", `WIFI:T:WPA;S:${esc(ssid)};P:${esc(password)};;`];
        qrProc.running = false;
        qrProc.running = true;
    }
    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: root.qr = text.split("\n").filter(l => l.length)
                .map(l => l.replace(/##/g, "1").replace(/  /g, "0"))
        }
        onExited: code => { if (code !== 0) root.qr = []; }
    }

    // While it's on: who joined, and whether it's still on.
    Timer { running: root.active; repeat: true; interval: 5000; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
