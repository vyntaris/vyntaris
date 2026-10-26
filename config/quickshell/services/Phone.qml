pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property bool enabled: Config.phone.enabled
    property bool running: false
    property string name: ""
    property var devices: []
    property string failure: ""

    readonly property var paired: devices.filter(d => d.pairState === 3)
    readonly property var phone: paired.find(d => d.reachable) ?? null
    readonly property var asking: devices.filter(d => d.pairState === 2)
    readonly property var nearby: devices.filter(d => d.reachable && (d.pairState === 0 || d.pairState === 1))

    function iconFor(d) { return /tablet/.test(d?.type ?? "") ? "tablet" : /desktop|laptop/.test(d?.type ?? "") ? "laptop" : "smartphone"; }

    function setEnabled(on) {
        Config.phone.enabled = on;
        Config.saveSoon();
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "vyntaris-phone.service"]);
    }

    function send(cmd) {
        if (!link.connected) return;
        failure = "";
        link.write(JSON.stringify(cmd) + "\n");
        link.flush();
    }
    function ring(id) { send({ do: "ring", id }); }
    function clipboard(id) { send({ do: "clipboard", id }); }
    function share(id, paths) { send({ do: "share", id, paths }); }
    function pick(id) { send({ do: "pick", id }); }
    function pair(id) { send({ do: "pair", id }); }
    function unpair(id) { send({ do: "unpair", id }); }
    function accept(id) { send({ do: "accept", id }); }
    function reject(id) { send({ do: "reject", id }); }
    function feature(id, plugin, on) { send({ do: "feature", id, plugin, on }); }
    function rename(text) { send({ do: "rename", name: text }); }
    function refresh() { send({ do: "refresh" }); }

    Socket {
        id: link
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-phone.sock"
        parser: SplitParser {
            onRead: line => {
                let msg;
                try { msg = JSON.parse(line); } catch (e) { return; }
                if (msg.state) {
                    root.running = msg.state.running;
                    root.name = msg.state.name;
                    root.devices = msg.state.devices;
                } else if (msg.error) root.failure = msg.error;
            }
        }
        onConnectedChanged: if (!connected) { root.running = false; root.devices = []; if (root.enabled) again.restart(); }
        onError: if (root.enabled) again.restart()
    }
    onEnabledChanged: link.connected = enabled
    Component.onCompleted: link.connected = enabled
    Timer { id: again; interval: 1500; onTriggered: if (root.enabled && !link.connected) link.connected = true }
}
