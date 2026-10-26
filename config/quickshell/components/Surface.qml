import QtQuick
import qs.config

Rectangle {
    id: surface
    property bool accentMark: true
    property color tint: "transparent"

    radius: Theme.r(Theme.radius)
    border { width: 1; color: Theme.glassEdge }
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.glassTop }
        GradientStop { position: 1; color: Theme.glass }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: surface.tint
        Behavior on color { ColorAnim {} }
    }

    Rectangle {
        visible: parent.accentMark
        x: parent.radius + 6
        y: 0
        width: 22
        height: 2
        radius: 1
        color: Theme.accent
    }
}
