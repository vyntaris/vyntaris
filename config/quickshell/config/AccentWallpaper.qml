pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../components/WallpaperArt.js" as WallpaperArt
import "../components/LogoArt.js" as LogoArt

Singleton {
    id: root

    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"
    readonly property string dir: cacheHome + "/vyntaris/wallpapers"

    function hex(c) {
        const q = Qt.color(c);
        return "#" + [q.r, q.g, q.b].map(v => ("0" + Math.round(v * 255).toString(16)).slice(-2)).join("");
    }

    readonly property size pixels: {
        let w = 0, h = 0;
        for (const s of Quickshell.screens) {
            const k = s.devicePixelRatio || 1;
            if (s.width * k * s.height * k > w * h) { w = s.width * k; h = s.height * k; }
        }
        if (w < 640 || h < 360) { w = 2560; h = 1440; }
        const cap = Math.min(1, 3840 / w, 2160 / h);
        return Qt.size(Math.round(w * cap), Math.round(h * cap));
    }

    readonly property var colors: {
        const pal = Theme.basePalette, name = Theme.accentName;
        return {
            crust: hex(pal.crust), mantle: hex(pal.mantle), base: hex(pal.base), text: hex(pal.text),
            accent: hex(Theme.accentIn(pal)), partner: hex(LogoArt.partner(pal, name)), dark: Theme.isDark,
        };
    }
    readonly property string signature: JSON.stringify([colors, pixels.width, pixels.height, 3])
    function nameFor(style) {
        const sig = style + signature;
        let h = 5381;
        for (let i = 0; i < sig.length; i++) h = (Math.imul(h, 33) ^ sig.charCodeAt(i)) >>> 0;
        return dir + "/vyntaris-" + style + "-" + h.toString(16) + ".png";
    }

    readonly property var styles: WallpaperArt.styles
    function styleOf(path) {
        if (!path) return styles[0].id;
        return path.startsWith("vyntaris:") ? path.slice(9) : "";
    }

    property var files: ({})
    property bool ready: false
    function fileFor(path) {
        return files[styleOf(path)] ?? files[styles[0].id] ?? "";
    }
    readonly property string file: fileFor(Config.wallpaper.path)

    onSignatureChanged: debounce.restart()
    Component.onCompleted: debounce.restart()
    Timer { id: debounce; interval: 250; onTriggered: root.draw() }

    function draw() {
        const inUse = styleOf(Config.wallpaper.path);
        const order = styles.map(s => s.id).sort((a, b) => (b === inUse) - (a === inUse));
        const args = ["sh", dir, String(pixels.width), String(pixels.height)];
        const targets = {};
        for (const id of order) {
            targets[id] = nameFor(id);
            svg.path = targets[id] + ".svg";
            svg.setText(WallpaperArt.scene(id, pixels.width, pixels.height, colors));
            args.push(targets[id]);
        }
        render.targets = targets;
        render.command = ["sh", "-c",
            'd=$1; w=$2; h=$3; shift 3; keep=" "; bad=0; '
            + 'for t; do keep="$keep$t "; '
            + 'if [ ! -s "$t" ]; then rsvg-convert -w "$w" -h "$h" "$t.svg" -o "$t.new" && mv "$t.new" "$t" || bad=1; fi; rm -f "$t.svg" "$t.new"; done; '
            + 'for f in "$d"/vyntaris-*; do case "$keep" in *" $f "*) ;; *) rm -f "$f" ;; esac; done; exit $bad']
            .concat(args);
        render.running = false;
        render.running = true;
    }
    FileView {
        id: svg
        blockWrites: true
        atomicWrites: false
        printErrors: false
    }
    Process {
        id: render
        property var targets: ({})
        onExited: code => {
            if (code !== 0) console.warn("accent wallpaper: rsvg-convert failed (" + code + ")");
            root.files = targets;
            root.ready = true;
        }
    }
}
