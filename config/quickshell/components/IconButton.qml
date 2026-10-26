import QtQuick
import qs.config

Rectangle {
    id: root
    property string icon
    property int size: 32
    property bool primary: false
    property bool on: false
    property bool active: true
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    opacity: active ? 1 : 0.35
    color: primary ? (area.containsMouse && active ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
                   : (area.containsMouse && active ? Theme.hover : "transparent")
    scale: area.pressed && active ? 0.9 : 1
    Behavior on color { ColorAnim {} }
    Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }

    Icon { anchors.centerIn: parent; name: root.icon; size: Math.round(root.size * 0.45); color: root.primary ? Theme.textOnAccent : root.on ? Theme.accent : Theme.text }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.active
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
