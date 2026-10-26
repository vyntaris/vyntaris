import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    PanelWindow {
        id: w
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "shot"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; left: true }
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        readonly property var crop: (Quickshell.env("SHOT_CROP") || "0,0,1920,1080,1").split(",").map(Number)
        Item {
            id: frame
            width: w.crop[2] * w.crop[4]
            height: w.crop[3] * w.crop[4]
            clip: true
            ScreencopyView {
                x: -w.crop[0] * w.crop[4]
                y: -w.crop[1] * w.crop[4]
                width: 1920 * w.crop[4]; height: 1080 * w.crop[4]
                captureSource: Quickshell.screens[0]
                live: false
                smooth: false
                onHasContentChanged: if (hasContent) grab.start()
            }
        }
        Timer { id: grab; interval: 100; onTriggered: frame.grabToImage(r => { r.saveToFile(Quickshell.env("SHOT_OUT")); Qt.quit(); }) }
        Timer { interval: 5000; running: true; onTriggered: Qt.quit() }
    }
}
