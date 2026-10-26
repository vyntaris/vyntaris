pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property string plugin: "/usr/lib/ladspa/librnnoise_ladspa.so"
    readonly property string nodeName: "vyntaris_noise_source"
    readonly property var labels: [Tr.t("Off"), Tr.t("Low"), Tr.t("Medium"), Tr.t("High"), Tr.t("Max")]
    readonly property var thresholds: [0, 0, 60, 85, 95]
    readonly property int level: Math.max(0, Math.min(4, Config.audio.noise))
    property bool available: false
    property bool installing: false

    function set(n) {
        n = Math.max(0, Math.min(4, Math.round(n)));
        if (n > 0 && !available) { install(n); return; }
        if (n > 0 && root.level === 0) {
            const mic = Pipewire.defaultAudioSource;
            if (mic && mic.name !== root.nodeName) Config.audio.noiseMic = mic.name;
        }
        Config.audio.noise = n;
        Config.saveSoon();
    }

    property int wanted: 0
    function install(n) {
        if (installing) return;
        wanted = n;
        installing = true;
        installer.running = true;
    }
    Process {
        id: installer
        command: ["pkexec", "pacman", "-S", "--needed", "--noconfirm", "noise-suppression-for-voice"]
        onExited: code => {
            root.installing = false;
            check.running = true;
            if (code === 0) after.restart();
        }
    }
    Timer { id: after; interval: 600; onTriggered: if (root.available) root.set(root.wanted) }
    Process {
        id: check
        command: ["test", "-e", root.plugin]
        running: true
        onExited: code => root.available = code === 0
    }

    readonly property string confDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/pipewire/filter-chain.conf.d"
    readonly property string conf: confDir + "/vyntaris-noise.conf"
    function confText() {
        const mic = Config.audio.noiseMic ? `        target.object = "${Config.audio.noiseMic}"\n` : "";
        return `# Written by the Vyntaris shell (Microphone › Noise suppression); changed and removed by it\n`
            + `context.modules = [\n{ name = libpipewire-module-filter-chain\n  args = {\n`
            + `    node.description = "Microphone (noise suppressed)"\n    media.name = "Noise suppression"\n`
            + `    filter.graph = { nodes = [ { type = ladspa name = rnnoise plugin = ${root.plugin} label = noise_suppressor_mono\n`
            + `        control = { "VAD Threshold (%)" = ${root.thresholds[root.level]}.0 "VAD Grace Period (ms)" = 200 "Retroactive VAD Grace (ms)" = 0 } } ] }\n`
            + `    capture.props = {\n        node.name = "capture.vyntaris_noise"\n        node.passive = true\n        audio.rate = 48000\n${mic}    }\n`
            + `    playback.props = {\n        node.name = "${root.nodeName}"\n        media.class = Audio/Source\n        audio.rate = 48000\n    }\n`
            + `  }\n}\n]\n`;
    }
    onLevelChanged: {
        apply.restart();
        if (level === 0 && Pipewire.defaultAudioSource?.name === root.nodeName) {
            const mic = Pipewire.nodes.values.find(n => n.name === Config.audio.noiseMic);
            if (mic) Pipewire.preferredDefaultAudioSource = mic;
        }
    }
    Component.onCompleted: apply.restart()
    Timer { id: apply; interval: 500; onTriggered: { applyProc.running = false; applyProc.running = true; } }
    Process {
        id: applyProc
        command: root.level > 0 && root.available
            ? ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.new" && mv "$1.new" "$1" && systemctl --user restart filter-chain.service', "sh", root.conf, root.confText()]
            : ["sh", "-c", 'if [ -e "$1" ]; then rm -f "$1"; systemctl --user stop filter-chain.service; fi', "sh", root.conf]
    }
    onAvailableChanged: apply.restart()

    readonly property var node: Pipewire.nodes.values.find(n => n.name === root.nodeName) ?? null
    onNodeChanged: if (node && level > 0) Pipewire.preferredDefaultAudioSource = node
}
