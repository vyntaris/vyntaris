pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool gameMode: false
    property bool nightLight: false

    function refresh() { gameAsk.running = true; nightAsk.running = true; }
    function toggle(target) {
        Panels.inShell(target, "toggle");
        if (target === "gamemode") gameMode = !gameMode; else nightLight = !nightLight;
        askAgain.restart();
    }
    Timer { id: askAgain; interval: 2200; onTriggered: root.refresh() }

    readonly property var shell: ["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call"]
    Process {
        id: gameAsk
        command: root.shell.concat(["gamemode", "status"])
        stdout: StdioCollector { onStreamFinished: root.gameMode = text.trim() === "on" }
    }
    Process {
        id: nightAsk
        command: root.shell.concat(["nightlight", "status"])
        stdout: StdioCollector { onStreamFinished: root.nightLight = text.trim() === "on" }
    }
    Component.onCompleted: refresh()
}
