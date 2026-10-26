pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var list: []
    property int jobs: 0
    property bool available: false

    function refresh() { if (!proc.running) proc.running = true; }
    function addPrinter() { Quickshell.execDetached(["system-config-printer"]); }
    function setDefault(name) {
        Quickshell.execDetached(["lpoptions", "-d", name]);
        later.restart();
    }
    function testPage(name) {
        Quickshell.execDetached(["sh", "-c", 'lp -d "$1" /usr/share/cups/data/testprint', "sh", name]);
        later.restart();
    }

    Timer { id: later; interval: 800; onTriggered: root.refresh() }

    Process {
        id: proc
        command: ["sh", "-c", "command -v lpstat >/dev/null || exit 3; "
            + "echo '#printers'; lpstat -p 2>/dev/null; echo '#default'; lpstat -d 2>/dev/null; "
            + "echo '#jobs'; lpstat -o 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const sections = {};
                let cur = "";
                for (const line of text.split("\n")) {
                    if (line.startsWith("#")) { cur = line.slice(1); sections[cur] = []; }
                    else if (cur && line.trim()) sections[cur].push(line.trim());
                }
                const def = ((sections["default"] ?? [])[0] ?? "").replace(/^.*:\s*/, "");
                root.list = (sections["printers"] ?? []).filter(l => l.startsWith("printer ")).map(l => {
                    const m = l.match(/^printer (\S+) (?:is )?(\w+)/);
                    return { name: m ? m[1] : l, state: m ? m[2] : "", default: m && m[1] === def };
                });
                root.jobs = parseInt((sections["jobs"] ?? ["0"])[0]) || 0;
                root.available = text.length > 0;
            }
        }
        onExited: code => { if (code === 3) root.available = false; }
    }
}
