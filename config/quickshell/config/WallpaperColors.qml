pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string file: Config.wallpaperFile()
    readonly property bool wanted: Config.theme.wallpaperAccent

    property bool ready: false
    property color vibrant: "#cba6f7"
    property string chosen: ""

    readonly property string picture: Config.wallpaperPath
    onFileChanged: if (wanted) later(Theme.duration(950) + 250)
    onPictureChanged: if (wanted) later(Theme.duration(950) + 250)
    onWantedChanged: if (wanted) later(300)
    Component.onCompleted: if (wanted) later(300)
    function later(ms) { analyze.interval = ms; analyze.restart(); }

    Timer { id: analyze; interval: 300; onTriggered: root.look() }

    function look() {
        if (Config.wallpaperPending()) { later(500); return; }
        // The default picture's lights are painted in the accent, so it has no colour of its own to give.
        if (Config.wallpaperPath === Config.defaultWallpaper) {
            proc.running = false;
            vibrant = AccentWallpaper.baked;
            chosen = "mauve";
            ready = true;
            apply();
            return;
        }
        proc.running = false;
        proc.running = true;
    }

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

        // The hue that covers most of the picture wins; near black and grey say nothing about it.
        const hues = {};
        for (const e of colors) {
            if (e.c.hsvValue < 0.2 || e.c.hsvSaturation < 0.15) continue;
            const hue = Math.round(e.c.hsvHue * 12) % 12;
            const h = hues[hue] ?? (hues[hue] = { count: 0, top: e });
            h.count += e.count;
            if (e.count > h.top.count) h.top = e;
        }
        const winner = Object.values(hues).sort((x, y) => y.count - x.count)[0];
        vibrant = winner ? winner.top.c : colors[0].c;
        chosen = winner ? hex(winner.top.c) : "lavender";
        ready = true;
        apply();
    }

    function hex(c) {
        const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2);
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    function apply() {
        if (!Config.leader || !ready || !Config.theme.wallpaperAccent || !chosen) return;
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
