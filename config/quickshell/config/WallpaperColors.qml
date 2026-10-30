pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string file: Config.wallpaperFile()
    readonly property bool wanted: Config.theme.wallpaperAccent && !Config.isAccentWallpaper(Config.wallpaper.path)

    property bool ready: false
    property color vibrant: "#cba6f7"
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

        let best = null, bestScore = -1, dim = null, dimScore = -1;
        for (const e of colors) {
            const s = e.c.hsvSaturation, v = e.c.hsvValue;
            const score = Math.sqrt(e.count / total) * s * v;
            if (v >= 0.4 && s >= 0.12 && score > bestScore) { bestScore = score; best = e; }
            if (v > 0.25 && score > dimScore) { dimScore = score; dim = e; }
        }
        best = best ?? dim ?? colors[0];
        vibrant = best.c;

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
}
