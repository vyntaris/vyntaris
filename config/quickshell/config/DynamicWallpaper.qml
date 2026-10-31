pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/vyntaris/dynamic"
    property var sets: ({})
    property var queue: []

    function folderOf(path) {
        let h = 5381;
        for (let i = 0; i < path.length; i++) h = (Math.imul(h, 33) ^ path.charCodeAt(i)) >>> 0;
        return dir + "/" + h.toString(16);
    }

    function known(path) {
        return sets[path] !== undefined;
    }

    function fileAt(path, minute) {
        const set = sets[path];
        if (!set) {
            Qt.callLater(prepare, path);
            return "";
        }
        if (set.schedule.length === 0) return "";
        let frame = set.schedule[set.schedule.length - 1].i;
        for (const entry of set.schedule)
            if (entry.m <= minute) frame = entry.i;
        return set.folder + "/frame-" + frame + ".jpg";
    }

    function prepare(path) {
        if (sets[path] || queue.includes(path)) return;
        queue = queue.concat([path]);
        next();
    }

    function next() {
        if (extract.running || queue.length === 0) return;
        extract.path = queue[0];
        extract.running = true;
    }

    function finished(text) {
        let schedule = [];
        try { schedule = JSON.parse(text); } catch (e) {}
        const done = Object.assign({}, sets);
        done[extract.path] = { folder: folderOf(extract.path), schedule: schedule };
        sets = done;
        queue = queue.slice(1);
        Qt.callLater(next);
    }

    Process {
        id: extract
        property string path: ""
        command: ["sh", "-c",
            'f=$1; d=$2; stamp="$(stat -c "%Y %s" "$f")" || exit 1; '
            + 'if [ "$(cat "$d/stamp" 2>/dev/null)" != "$stamp" ] || [ ! -s "$d/schedule.json" ]; then '
            + '  mkdir -p "$d" && rm -f "$d"/frame-* "$d/stamp"; '
            + '  /usr/lib/vyntaris/json heic-schedule "$f" > "$d/schedule.json" || echo \'[{"m":0,"i":0}]\' > "$d/schedule.json"; '
            + '  nice -n 19 magick "$f" -quality 92 "$d/frame-%d.jpg" || { rm -f "$d/schedule.json"; exit 1; }; '
            + '  printf "%s" "$stamp" > "$d/stamp"; '
            + 'fi; cat "$d/schedule.json"',
            "sh", path.slice(5), root.folderOf(path)]
        stdout: StdioCollector { onStreamFinished: root.finished(text) }
    }
}
