import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root
    property string text
    property string icon
    property bool primary: false
    property bool danger: false
    property bool active: true
    signal clicked()

    readonly property color fill: danger ? Theme.error : Theme.accent
    readonly property bool filled: primary || danger
    readonly property bool iconOnly: text === ""
    TextMetrics { id: measure; font: label.font; text: root.text }
    readonly property real natural: measure.advanceWidth + (icon !== "" ? 23 : 0) + 32
    readonly property bool tight: !iconOnly && width < natural

    implicitHeight: Theme.controlHeight
    implicitWidth: iconOnly ? implicitHeight : natural
    radius: Theme.r(implicitHeight / 2)
    opacity: active ? 1 : 0.4
    color: filled ? (area.containsMouse && active ? Qt.lighter(fill, 1.08) : fill)
                  : (area.containsMouse && active ? Theme.alpha(Theme.text, 0.12) : Theme.alpha(Theme.text, 0.06))
    border { width: filled ? 0 : 1; color: Theme.glassRim }
    scale: area.pressed && active ? 0.95 : 1
    Behavior on color { ColorAnim {} }
    Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon { visible: root.icon !== "" && (root.iconOnly || !root.tight); name: root.icon; size: 15; color: root.filled ? Theme.textOnAccent : Theme.text }
        Label {
            id: label
            visible: !root.iconOnly
            Layout.maximumWidth: Math.max(0, root.width - 20)
            elide: Text.ElideRight
            font.weight: Font.DemiBold
            color: root.filled ? Theme.textOnAccent : Theme.text
            text: root.text
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.active) root.clicked()
    }
}
