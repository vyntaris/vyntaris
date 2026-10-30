import QtQuick
import qs.config

Item {
    id: root
    property string icon
    signal clicked()
    implicitWidth: 26
    implicitHeight: 26
    Rectangle {
        anchors.fill: parent
        radius: 13
        color: area.containsMouse ? Theme.accent : "transparent"
        Behavior on color { ColorAnim {} }
    }
    Icon { anchors.centerIn: parent; name: root.icon; size: 15; color: area.containsMouse ? Theme.textOnAccent : Theme.overlay1 }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
