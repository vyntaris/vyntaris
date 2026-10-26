import QtQuick
import qs.config

Rectangle {
    id: root
    property bool checked: false
    signal toggled(bool on)

    implicitWidth: 42
    implicitHeight: 24
    radius: Theme.r(height / 2)
    color: checked ? Theme.accent : Theme.alpha(Theme.text, 0.12)
    border { width: 1; color: Theme.glassRim }
    Behavior on color { ColorAnim {} }

    Rectangle {
        width: 18; height: 18; radius: Theme.r(9)
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: root.checked ? Theme.textOnAccent : Theme.overlay2
        Behavior on x { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
