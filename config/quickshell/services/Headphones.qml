pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// Wired headphones in the jack: the default output's active port is a headphone port the card
// says is plugged in. Bluetooth headphones are shown by the bar's Bluetooth module instead.
Singleton {
    id: root

    property bool connected: false

    Process {
        id: events
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser { onRead: line => { if (/ on (card|sink|server) /.test(line)) settle.restart(); } }
        onExited: retry.restart()
    }
    Timer { id: retry; interval: 5000; onTriggered: events.running = true }
    Timer { id: settle; interval: 300; onTriggered: if (!reader.running) reader.running = true }

    Process {
        id: reader
        running: true
        command: ["sh", "-c", "pactl get-default-sink; pactl -f json list sinks"]
        stdout: StdioCollector {
            onStreamFinished: {
                const nl = text.indexOf("\n");
                try { root.update(text.slice(0, nl).trim(), JSON.parse(text.slice(nl + 1))); }
                catch (e) { console.warn("headphones:", e); }
            }
        }
    }

    property bool known: false
    function update(name, sinks) {
        const sink = sinks.find(s => s.name === name);
        const port = (sink?.ports ?? []).find(p => p.name === sink.active_port);
        const now = !!port && sink.properties?.["device.api"] !== "bluez5"
            && (port.type === "Headphones" || /headphone/i.test(port.name))
            && port.availability !== "not available";
        if (now && !connected && known)
            Activities.banner("headphones", Tr.t("Headphones connected"), "", -1, Theme.accent, 2500);
        connected = now;
        known = true;
    }
}
