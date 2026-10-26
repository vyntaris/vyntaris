import QtQuick
import qs.config

Rectangle {
    id: root
    required property string accent
    property real size: 30
    readonly property bool current: Theme.accentName === accent && !Config.theme.wallpaperAccent

    width: size
    height: size
    radius: size / 2
    color: Theme.palette[accent]
    scale: area.containsMouse && !current ? 1.12 : 1
    Behavior on scale { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }

    Icon { anchors.centerIn: parent; visible: root.current; name: "check"; size: Math.round(root.size * 0.44); stroke: 2.4; color: Theme.textOnAccent }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Config.setAccent(root.accent) }
}
