import Quickshell
import QtQuick
import qs.config
import "../../config/Wallpapers.js" as Walls

Scope {
    id: root

    readonly property string file: Config.wallpaperFile()
    readonly property string resize: ({ crop: "crop", fit: "fit", stretch: "stretch" })[Config.wallpaper.fillMode] ?? "crop"
    readonly property string fill: String(Theme.crust).slice(1, 7)
    readonly property bool waiting: Config.wallpaperPending()
    readonly property bool accentFollows: WallpaperColors.wanted
    readonly property string picture: [file, resize, fill, waiting].join("\n")

    property bool started: false
    onPictureChanged: showSoon.restart()
    Component.onCompleted: show()
    Timer { id: showSoon; interval: 40; onTriggered: root.show() }

    function show() {
        if (waiting) return;
        const timed = Walls.isDynamic(Config.wallpaperPath);
        const ms = !started ? 0 : timed ? 3000 : Theme.duration(950);
        started = true;
        Quickshell.execDetached(["sh", "-c",
            'for i in $(seq 40); do awww query >/dev/null 2>&1 && break; sleep 0.25; done; f="$1"; [ -r "$f" ] || f="$2"; '
            + 'exec awww img "$f" --resize "$3" --fill-color "$4" --transition-type "$5" --transition-pos center '
            + '--transition-duration "$6" --transition-fps 60 --transition-bezier .65,0,.35,1',
            "sh", file, Config.defaultWallpaper, resize, fill, ms === 0 ? "none" : timed ? "fade" : "grow", String(ms / 1000)]);
    }
}
