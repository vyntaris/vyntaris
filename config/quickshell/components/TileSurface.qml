import QtQuick
import qs.config

Rectangle {
    id: root
    property bool marked: false
    property bool solid: false
    property real pressScale: 0.97
    readonly property alias hovered: area.containsMouse
    readonly property alias pressed: area.pressed
    property alias acceptedButtons: area.acceptedButtons
    signal activated(var mouse)
    signal entered()

    radius: Theme.r(16)
    readonly property color fill: marked && solid ? (hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
        : marked ? Theme.alpha(Theme.accent, hovered ? 0.3 : 0.22)
        : hovered ? Theme.alpha(Theme.text, 0.09) : Theme.alpha(Theme.text, 0.05)
    readonly property color edge: marked && solid ? Theme.accent : marked ? Theme.alpha(Theme.accent, 0.55) : Theme.glassRim
    color: slant.on ? "transparent" : fill
    border { width: slant.on ? 0 : 1; color: edge }
    Slanted { id: slant; fill: root.fill; stroke: root.edge; radius: root.radius }
    scale: pressed ? pressScale : 1
    Behavior on color { ColorAnim {} }
    Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.activated(mouse)
        onEntered: root.entered()
    }
}
