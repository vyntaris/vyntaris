pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/vyntaris/accent-wallpaper"
    // default.jpg already has this colour in its lights.
    readonly property string baked: "#cba6f7"
    readonly property string accent: String(Theme.accent)
    property string ready: ""
    readonly property string file: !ready || ready === baked ? Config.defaultWallpaper : dir + "/" + ready.slice(1) + ".jpg"

    onAccentChanged: paint.restart()
    Component.onCompleted: paint.restart()
    Timer { id: paint; interval: 200; onTriggered: { proc.running = false; proc.running = true; } }

    Process {
        id: proc
        command: ["sh", "-c",
            'hex=$1; d=$2; picture=$3; source=${picture%.*}-base.jpg; lights=${picture%.*}-lights.png; out="$d/${hex#\\#}.jpg"; '
            + 'stamp="$(stat -c "%Y %s" "$source")" || exit 1; mkdir -p "$d" || exit 1; '
            + '[ "$(cat "$d/stamp" 2>/dev/null)" = "$stamp" ] || { rm -f "$d"/*.jpg; printf "%s" "$stamp" > "$d/stamp"; }; '
            + 'if [ "$hex" = "$4" ]; then out=$picture; elif [ ! -s "$out" ]; then '
            + '  nice -n 19 magick "$source" \\( +clone -separate -evaluate-sequence Max -colorspace sRGB -type TrueColor '
            + '    \\( +clone -fill "$hex" -colorize 100 \\) -compose Multiply -composite \\) "$lights" -compose Over -composite '
            + '    -sampling-factor 1x1 -quality 92 "$out.tmp.jpg" && mv "$out.tmp.jpg" "$out" || exit 1; '
            + 'fi; '
            + 'find "$d" -name "*.jpg" ! -name "${out##*/}" ! -name current.jpg -delete; '
            + 'cp "$out" "$d/current.tmp" && mv "$d/current.tmp" "$d/current.jpg"; printf "%s" "$hex"',
            "sh", root.accent, root.dir, Config.defaultWallpaper, root.baked]
        stdout: StdioCollector { onStreamFinished: if (text.trim() === root.accent) root.ready = root.accent }
    }
}
