pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var rates: null
    readonly property string file: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/vyntaris/rates.json"

    function want() {
        if (fetch.running) return;
        if (rates && Date.now() / 1000 - rates.fetched < 12 * 3600) return;
        fetch.running = true;
    }

    FileView {
        id: cache
        path: root.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const r = JSON.parse(text());
                if (r.result !== "success" || !r.rates) return;
                root.rates = { base: r.base_code, rates: r.rates, fetched: r.fetched ?? 0,
                               date: Qt.formatDate(new Date(r.time_last_update_unix * 1000), "d MMM") };
            } catch (e) {}
        }
    }
    Process {
        id: fetch
        command: ["sh", "-c", 'mkdir -p "$(dirname "$1")" && curl -fsS --max-time 8 https://open.er-api.com/v6/latest/EUR '
            + '| sed "1s/^{/{\\"fetched\\":$(date +%s),/" > "$1.new" && [ -s "$1.new" ] && mv "$1.new" "$1"', "sh", root.file]
    }
}
