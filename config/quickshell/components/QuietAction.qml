import QtQuick
import qs.config

Rectangle {
    id: root
    property string icon
    property string text
    property color ink: Theme.subtext0
    property color hoverFill: Theme.error
    property color hoverInk: Theme.textOnAccent
    signal clicked()

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 32
    radius: Theme.r(10)
    color: area.containsMouse ? hoverFill : "transparent"
    Behavior on color { ColorAnim {} }

    Row {
        id: row
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 8
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.icon
            size: 14
            color: area.containsMouse ? root.hoverInk : root.ink
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: Theme.fontSizeSmall + 1
            color: area.containsMouse ? root.hoverInk : root.ink
            text: root.text
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
