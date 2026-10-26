pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var entries: []

    function refresh() {
        list.running = true;
    }

    function copy(entry) {
        Quickshell.execDetached(["sh", "-c", `printf '%s\\t' "$1" | cliphist decode | wl-copy`, "sh", entry.id]);
    }

    Process {
        id: list
        command: ["sh", "-c", "command -v cliphist >/dev/null && cliphist list | head -n 200"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.includes("\t")).map(l => {
                    const i = l.indexOf("\t");
                    const body = l.slice(i + 1);
                    return { id: l.slice(0, i), text: body, isImage: body.startsWith("[[ binary data") };
                });
            }
        }
    }
}
