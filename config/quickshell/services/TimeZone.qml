pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string current: ""
    property var all: []
    property var countries: ({})

    function refresh() { cur.running = true; if (all.length === 0) { list.running = true; places.running = true; } }
    function set(zone) {
        if (!all.includes(zone)) return;
        setter.command = ["timedatectl", "set-timezone", zone];
        setter.running = true;
    }

    function city(zone) { return (zone ?? "").split("/").pop().replace(/_/g, " "); }
    function country(zone) { return countries[zone] ?? (zone ?? "").split("/")[0].replace(/_/g, " "); }

    function search(text, max) {
        const q = text.trim().toLowerCase().replace(/_/g, " ");
        if (!q) return [];
        const at = s => s.toLowerCase().split(/[\s/-]+/).some(w => w.startsWith(q)) || s.toLowerCase().startsWith(q);
        const byCity = all.filter(z => at(city(z)));
        const byCountry = all.filter(z => !byCity.includes(z) && at(country(z)));
        return byCity.concat(byCountry).slice(0, max ?? 6);
    }

    Process {
        id: cur
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector { onStreamFinished: root.current = text.trim() }
    }
    Process {
        id: list
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { onStreamFinished: root.all = text.trim().split("\n") }
    }
    Process {
        id: places
        command: ["awk", "-F\t", "NR == FNR { if ($0 !~ /^#/) name[$1] = $2; next } $0 !~ /^#/ { print $3 \"\t\" name[$1] }",
                  "/usr/share/zoneinfo/iso3166.tab", "/usr/share/zoneinfo/zone.tab"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.split("\n")) {
                    const [zone, name] = line.split("\t");
                    if (zone && name) map[zone] = name;
                }
                root.countries = map;
            }
        }
    }
    Process {
        id: setter
        onExited: cur.running = true
    }
    Component.onCompleted: refresh()
}
