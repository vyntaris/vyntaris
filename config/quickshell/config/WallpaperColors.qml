pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string file: Config.wallpaperFile()
    readonly property bool wanted: (Config.theme.wallpaperAccent || Config.theme.wallpaperTint) && !Config.isAccentWallpaper(Config.wallpaper.path)

    property bool ready: false
    property color vibrant: "#cba6f7"
    property real tintHue: 0.7
    property real tintStrength: 0
    property string chosen: ""

    onFileChanged: if (wanted) later(Theme.duration(950) + 250)
    onWantedChanged: if (wanted) later(300)
    Component.onCompleted: if (wanted) later(300)
    function later(ms) { analyze.interval = ms; analyze.restart(); }

    Timer { id: analyze; interval: 300; onTriggered: { proc.running = false; proc.running = true; } }

    Process {
        id: proc
        command: ["magick", root.file + "[0]", "-resize", "96x96^", "-colors", "12", "-depth", "8", "-format", "%c", "histogram:info:-"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    function parse(text) {
        const colors = [];
        let total = 0;
        for (const line of text.split("\n")) {
            const m = line.match(/^\s*(\d+):.*?(#[0-9A-Fa-f]{6})/);
            if (!m) continue;
            const count = Number(m[1]);
            const c = Qt.color(m[2]);
            colors.push({ count, c });
            total += count;
        }
        if (colors.length === 0) return;

        let best = null, bestScore = -1, dim = null, dimScore = -1, tint = null, tintCount = -1;
        for (const e of colors) {
            const s = e.c.hsvSaturation, v = e.c.hsvValue;
            const score = Math.sqrt(e.count / total) * s * v;
            if (v >= 0.4 && s >= 0.12 && score > bestScore) { bestScore = score; best = e; }
            if (v > 0.25 && score > dimScore) { dimScore = score; dim = e; }
            if (s > 0.12 && e.count > tintCount) { tintCount = e.count; tint = e; }
        }
        best = best ?? dim ?? colors[0];
        vibrant = best.c;

        const source = tint ?? best;
        tintHue = Math.max(0, source.c.hslHue);
        tintStrength = Math.min(1, source.c.hslSaturation * 1.5);

        chosen = best.c.hsvSaturation < 0.12 ? "lavender" : hex(best.c);
        ready = true;
        apply();
    }

    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    function apply() {
        if (!ready || !Config.theme.wallpaperAccent || !chosen) return;
        if (Config.theme.accent === chosen && Config.theme.accentLight === chosen) return;
        Config.theme.accent = chosen;
        Config.theme.accentLight = chosen;
        Config.save();
    }
    Connections {
        target: Config.theme
        function onWallpaperAccentChanged() { root.apply(); }
    }

    readonly property var neutrals: ({
        text: 0.45, subtext1: 0.5, subtext0: 0.55, overlay2: 0.7, overlay1: 0.75, overlay0: 0.8,
        surface2: 0.9, surface1: 0.95, surface0: 1, base: 1, mantle: 1, crust: 1,
    })

    function tint(p) {
        const out = Object.assign({}, p);
        for (const key in neutrals) {
            const c = Qt.color(p[key]);
            const s = Math.min(0.6, Math.max(c.hslSaturation, 0.1) * neutrals[key] * (0.6 + tintStrength * 0.6));
            out[key] = Qt.hsla(tintHue, s, c.hslLightness, 1).toString();
        }
        return out;
    }
}
