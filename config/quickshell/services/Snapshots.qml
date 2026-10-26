pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    property var list: []

    function refresh() { file.reload(); }

    function create() {
        Config.runInTerminal('sudo timeshift --create --comments "manual" --tags O && sudo /usr/lib/vyntaris/snapshots; ' + Config.enterToClose(true));
    }

    function openTimeshift() {
        Quickshell.execDetached(["timeshift-launcher"]);
    }

    FileView {
        id: file
        path: "/var/lib/vyntaris/snapshots.tsv"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.list = text().split("\n").filter(l => l.includes("\t")).map(l => {
                const f = l.split("\t");
                const name = f[0];
                return { name, date: name.replace("_", " ").replace(/-(\d\d)-(\d\d)$/, ":$1:$2"),
                         tags: f[1] ?? "", comment: f[2] ?? "" };
            }).reverse();
        }
        onLoadFailed: root.list = []
    }
}
