pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool watching: false
    property var outputs: []
    property var inputs: []

    onWatchingChanged: if (watching) refresh()
    function refresh() { if (!reader.running) reader.running = true; else again = true; }
    property bool again: false

    Process {
        id: reader
        command: [Quickshell.shellPath("scripts/audio-devices.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.build(JSON.parse(text)); } catch (e) { console.warn("sound devices:", e); }
                if (root.again) { root.again = false; root.refresh(); }
                root.finishPick();
            }
        }
    }
    Process {
        id: events
        running: root.watching
        command: ["pactl", "subscribe"]
        stdout: SplitParser { onRead: line => { if (/ on (card|sink|source|server) /.test(line)) settle.restart(); } }
    }
    Timer { id: settle; interval: 250; onTriggered: root.refresh() }

    property var data: ({ cards: [], sinks: [], sources: [] })
    property string defaultSink: ""
    property string defaultSource: ""
    Process {
        id: defaults
        command: ["sh", "-c", "pactl get-default-sink; pactl get-default-source"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.defaultSink = l[0] ?? "";
                root.defaultSource = l[1] ?? "";
                root.build(root.data);
            }
        }
    }

    function icon(type, label) {
        const t = (type + " " + label).toLowerCase();
        return /headphone|headset/.test(t) ? "headphones"
            : /hdmi|displayport|spdif/.test(t) ? "monitor"
            : /bluetooth|bluez/.test(t) ? "bluetooth"
            : /mic|input/.test(t) ? "mic"
            : "volume";
    }

    function build(d) {
        data = d;
        const out = [], inn = [];
        const cardNames = new Set();
        for (const c of d.cards ?? []) {
            cardNames.add(c.name);
            const desc = c.properties?.["device.description"] || c.name;
            const bluetooth = (c.properties?.["device.api"] || "") === "bluez5";
            for (const [pname, p] of Object.entries(c.ports ?? {})) {
                const profiles = p.profiles ?? [];
                const isOut = profiles.some(n => n.includes("output:") || n.startsWith("a2dp") || n.startsWith("headset"));
                const isIn = profiles.some(n => n.includes("input:"));
                if (!isOut && !isIn) continue;
                const nodes = isOut && !isIn ? d.sinks : isIn && !isOut ? d.sources : (pname.includes("input") ? d.sources : d.sinks);
                const node = (nodes ?? []).find(n => n.properties?.["device.name"] === c.name && !String(n.name).endsWith(".monitor"));
                const asInput = nodes === d.sources;
                const entry = {
                    key: c.name + "/" + pname, label: p.description || pname, sub: desc,
                    type: bluetooth ? "bluetooth" : p.type || "", icon: icon(bluetooth ? "bluetooth" : p.type || "", p.description || pname),
                    available: p.availability !== "not available" && profiles.some(n => c.profiles?.[n]?.available !== false),
                    takenOver: p.availability === "not available" && profiles.includes(c.active_profile),
                    card: c.name, port: pname, profiles, node: node?.name ?? "",
                    current: !!node && node.name === (asInput ? root.defaultSource : root.defaultSink) && node.active_port === pname,
                };
                (asInput ? inn : out).push(entry);
            }
        }
        const loose = (list, into, isInput) => {
            for (const n of list ?? []) {
                if (cardNames.has(n.properties?.["device.name"]) || String(n.name).endsWith(".monitor") || n.properties?.["device.class"] === "monitor") continue;
                const label = n.description || n.name;
                into.push({ key: n.name, label, sub: isInput ? "Virtual microphone" : "Virtual output", type: "", icon: icon("", label),
                            available: true, takenOver: false, card: "", port: "", profiles: [], node: n.name,
                            current: n.name === (isInput ? root.defaultSource : root.defaultSink) });
            }
        };
        loose(d.sinks, out, false);
        loose(d.sources, inn, true);
        const order = (a, b) => (b.available - a.available) || (b.takenOver - a.takenOver) || a.label.localeCompare(b.label);
        const shown = e => e.available || e.takenOver || e.icon !== "monitor";
        outputs = out.filter(shown).sort(order);
        inputs = inn.filter(shown).sort(order);
    }
    onDataChanged: if (!defaults.running) defaults.running = true

    property var pending: null
    function pick(e, isInput) {
        if (!e.available) return;
        if (!e.card) { run(["pactl", isInput ? "set-default-source" : "set-default-sink", e.node]); return; }
        const card = (data.cards ?? []).find(c => c.name === e.card);
        const ok = e.profiles.filter(n => card?.profiles?.[n]?.available !== false);
        if (!ok.includes(card?.active_profile)) {
            const both = ok.find(n => n.includes("output:") && n.includes("input:"));
            const stereo = ok.find(n => /stereo/.test(n));
            pending = { e, isInput };
            run(["pactl", "set-card-profile", e.card, both || stereo || ok[0]]);
            later.restart();
            return;
        }
        pending = { e, isInput };
        finishPick();
    }
    Timer { id: later; interval: 400; onTriggered: root.refresh() }
    function finishPick() {
        if (!pending) return;
        const { e, isInput } = pending;
        const nodes = isInput ? data.sources : data.sinks;
        const node = (nodes ?? []).find(n => n.properties?.["device.name"] === e.card && !String(n.name).endsWith(".monitor"));
        if (!node) return;
        pending = null;
        run(["sh", "-c", 'pactl "$1" "$2" "$3"; pactl "$4" "$2"', "sh",
             isInput ? "set-source-port" : "set-sink-port", node.name, e.port,
             isInput ? "set-default-source" : "set-default-sink"]);
    }
    function run(cmd) {
        Quickshell.execDetached(cmd);
        settle.restart();
    }
}
