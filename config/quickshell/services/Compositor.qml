pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    property int fullscreenMode: 0
    property string activeClass: ""
    property string activeContentType: ""

    function dispatch(expr) {
        Hyprland.dispatch(expr);
    }

    function focusWorkspace(id) {
        dispatch(`hl.dsp.focus({ workspace = ${id} })`);
    }

    function cycleWorkspace(step) {
        dispatch(`hl.dsp.focus({ workspace = "e${step > 0 ? "+" : "-"}1" })`);
    }

    function toggleSpecial(name) {
        dispatch(`hl.dsp.workspace.toggle_special("${name}")`);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (/^(fullscreen|activewindow|activewindowv2|workspace|workspacev2|closewindow|focusedmon|movewindow)$/.test(event.name))
                poll.restart();
        }
    }
    Timer { id: poll; interval: 60; onTriggered: if (!state.running) state.running = true }
    Process {
        id: state
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    root.fullscreenMode = w.fullscreen ?? 0;
                    root.activeClass = w.class || w.initialClass || "";
                    root.activeContentType = w.contentType ?? "";
                } catch (e) {
                    root.fullscreenMode = 0;
                    root.activeClass = "";
                    root.activeContentType = "";
                }
            }
        }
    }
    Component.onCompleted: state.running = true
}
