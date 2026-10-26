import Quickshell
import QtQuick

LazyLoader {
    id: root
    property bool open: false
    property int keepFor: 120000
    property bool kept: false

    active: open || kept
    Component.onCompleted: kept = open
    onOpenChanged: {
        if (open) { kept = true; release.stop(); }
        else release.restart();
    }
    property Timer release: Timer {
        interval: root.keepFor
        onTriggered: root.kept = false
    }
}
