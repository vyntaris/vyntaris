import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Scope {
    id: root

    SystemClock { id: clock; precision: SystemClock.Minutes }

    function minutes(s) {
        const t = (s || "0:0").split(":").map(Number);
        return t[0] * 60 + (t[1] || 0);
    }
    readonly property bool day: {
        const n = clock.date.getHours() * 60 + clock.date.getMinutes();
        const a = minutes(Config.theme.lightFrom), b = minutes(Config.theme.darkFrom);
        return a <= b ? n >= a && n < b : n >= a || n < b;
    }
    readonly property string wanted: day ? "latte" : (Config.theme.darkFlavor || "mocha")

    function follow() {
        if (Config.theme.autoFlavor && Config.theme.flavor !== wanted) {
            Config.theme.flavor = wanted;
            Config.save();
        }
    }
    onWantedChanged: follow()
    Connections {
        target: Config.theme
        function onAutoFlavorChanged() { root.follow(); }
    }
    Component.onCompleted: follow()

    readonly property bool dark: Theme.isDark
    onDarkChanged: {
        if (/^(times|heic):/.test(Config.wallpaperPath)) return;
        const path = Config.wallpaper.path;
        const m = path.match(/^(.*?)(-light)?(\.[A-Za-z0-9]+)$/);
        if (!m) return;
        const twin = dark ? m[1] + m[3] : m[1] + "-light" + m[3];
        if (twin === path) return;
        twinCheck.twin = twin;
        twinCheck.command = ["test", "-f", Config.expandHome(twin)];
        twinCheck.running = true;
    }
    Process {
        id: twinCheck
        property string twin
        onExited: code => {
            if (code !== 0) return;
            Config.wallpaper.path = twin;
            Config.save();
        }
    }
}
