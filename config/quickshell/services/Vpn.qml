pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property var list: []
    readonly property var active: list.find(v => v.active) ?? null
    property string busy: ""
    property string error: ""
    property var places: []
    readonly property string riseup: Quickshell.shellPath("scripts/riseup.sh")

    function findPlaces() { if (!placer.running) placer.running = true; }

    function place(name) {
        const on = list.find(v => v.place === name);
        if (on) return toggle(on);
        if (busy) return;
        error = "";
        busy = "riseup:" + name;
        run([riseup, "connect", name], null);
    }

    function quick() {
        if (active) toggle(active);
        else if (list.length > 0) toggle(list[0]);
        else if (places.length > 0) place(places[0].name);
    }

    function refresh() { lister.running = true; }

    function toggle(v) {
        if (busy) return;
        error = "";
        busy = v.uuid;
        run(["nmcli", "connection", v.active ? "down" : "up", "uuid", v.uuid], v);
    }

    function run(cmd, v) {
        act.vpn = v;
        act.command = cmd;
        act.running = true;
    }

    Process {
        id: act
        property var vpn: null
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            const why = actErr.text.trim().replace(/^Error: /, "");
            if (code !== 0 && vpn && !vpn.active && /secrets were required|no agents were available/i.test(why))
                Config.runInTerminal(`nmcli --ask connection up uuid ${vpn.uuid}; ${Config.enterToClose()}`);
            else if (code !== 0)
                root.error = /plugin for openvpn|openvpn.*not (installed|available)/i.test(why)
                    ? Tr.t("OpenVPN's support for NetworkManager isn't installed (networkmanager-openvpn).")
                    : why.split("\n")[0] || Tr.t("It didn't work.");
            root.busy = "";
            root.refresh();
        }
    }

    Process {
        id: lister
        command: ["nmcli", "-t", "-f", "UUID,TYPE,ACTIVE,NAME", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const f = line.match(/^([0-9a-f-]{36}):([^:]*):([^:]*):(.*)$/);
                    if (!f || !/^(vpn|wireguard)$/.test(f[2])) continue;
                    const name = f[4].replace(/\\(.)/g, "$1");
                    out.push({ uuid: f[1], type: f[2] === "vpn" ? "OpenVPN" : "WireGuard", active: f[3] === "yes", name: name,
                               place: name.startsWith("Riseup · ") ? name.slice(9) : "" });
                }
                root.list = out.sort((a, b) => (b.active - a.active) || a.name.localeCompare(b.name));
            }
        }
    }

    Process {
        id: placer
        command: [root.riseup, "places"]
        stderr: StdioCollector { id: placerErr }
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(l => l).map(l => ({ name: l.split("\t")[0], country: l.split("\t")[1] ?? "" }));
                if (found.length > 0) root.places = found;
            }
        }
        onExited: code => { if (code !== 0 && root.places.length === 0) root.error = placerErr.text.trim(); }
    }

    Process {
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: settle.restart() }
    }
    Timer { id: settle; interval: 300; onTriggered: root.refresh() }

    Component.onCompleted: { refresh(); findPlaces(); }
}
