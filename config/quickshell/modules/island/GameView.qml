import QtQuick
import qs.config
import qs.services

Item {
    id: root
    readonly property real fullWidth: Math.max(Theme.notchWidth, stats.implicitWidth + 40)
    readonly property real hang: Theme.notchDepth

    width: fullWidth
    height: Theme.barHeight + hang

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Panels.controlOpen = !Panels.controlOpen
    }
    GameStatsRow {
        id: stats
        anchors.horizontalCenter: parent.horizontalCenter
        y: (Theme.barHeight + Theme.notchDepth - height) / 2
    }
}
