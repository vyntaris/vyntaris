import QtQuick
import qs.config

// Two rings, so one shows on whatever the control is filled with.
Rectangle {
    property real ringRadius: 0
    anchors.fill: parent
    visible: parent.activeFocus
    z: 100
    radius: ringRadius
    color: "transparent"
    border { width: 2; color: Theme.isDark ? Theme.text : Theme.palette.text }
    Rectangle {
        anchors { fill: parent; margins: Theme.space2 }
        radius: Math.max(0, parent.radius - 2)
        color: "transparent"
        border { width: 1; color: Theme.isDark ? Theme.crust : Theme.base }
    }
}
