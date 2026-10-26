import QtQuick
import qs.config

Item {
    id: root
    property string icon
    property string glyph
    property string label
    property color tint: Theme.accent
    property bool on: false
    property bool enabled: true
    property bool interactive: true
    signal clicked()
    signal rightClicked()
    signal entered()

    implicitWidth: 64
    implicitHeight: 74
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: circle
        anchors.horizontalCenter: parent.horizontalCenter
        width: 48
        height: 48
        radius: 24
        color: root.on ? root.tint : area.containsMouse && root.interactive ? Theme.alpha(Theme.text, 0.12) : Theme.alpha(Theme.text, 0.07)
        border { width: 1; color: root.on ? Theme.alpha(root.tint, 0.6) : Theme.glassRim }
        scale: area.pressed ? 0.9 : 1
        Behavior on color { ColorAnim {} }
        Behavior on scale { Anim { duration: Theme.durationFast; easing.bezierCurve: Theme.curveSpring } }

        Label {
            anchors.centerIn: parent
            visible: root.glyph !== ""
            mono: true
            font.weight: Font.Bold
            color: root.on ? Theme.textOnAccent : Theme.subtext1
            text: root.glyph
        }
        Icon {
            anchors.centerIn: parent
            visible: root.glyph === ""
            name: root.icon
            size: 19
            color: root.on ? Theme.textOnAccent : Theme.subtext1
        }
    }

    Label {
        anchors { horizontalCenter: parent.horizontalCenter; top: circle.bottom; topMargin: 7 }
        width: root.width + 8
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        caps: true
        font.pixelSize: Theme.fontSizeSmall - 2
        color: root.on ? (root.tint === Theme.accent ? Theme.text : root.tint) : Theme.overlay1
        text: root.label
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled && root.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
        onEntered: root.entered()
    }
}
