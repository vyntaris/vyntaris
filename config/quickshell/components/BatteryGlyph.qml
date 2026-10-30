import QtQuick
import QtQuick.Layouts
import qs.config

Item {
    id: root
    property real percent: 0
    property bool charging: false
    property color color: Theme.accent
    property real size: 22

    implicitWidth: size
    implicitHeight: Math.round(size * 0.55)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    readonly property real nub: Math.max(2, Math.round(size * 0.1))

    Rectangle {
        id: body
        width: parent.width - root.nub - 1
        height: parent.height
        radius: Math.round(height * 0.3)
        color: Qt.alpha(root.color, 0.28)

        Rectangle {
            id: fill
            height: parent.height
            width: parent.width * Math.max(0, Math.min(100, root.percent)) / 100
            radius: body.radius
            color: root.color
            Behavior on width { Anim {} }
            SequentialAnimation on opacity {
                running: root.charging && Theme.speed > 0
                loops: Animation.Infinite
                onRunningChanged: if (!running) fill.opacity = 1
                NumberAnimation { to: 0.5; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }
    Rectangle {
        anchors { left: body.right; leftMargin: 1; verticalCenter: body.verticalCenter }
        width: root.nub
        height: body.height * 0.42
        radius: width / 2
        color: root.percent >= 99 ? root.color : Qt.alpha(root.color, 0.28)
    }
    Icon {
        visible: root.charging
        anchors.centerIn: body
        name: "bolt"
        filled: true
        size: root.height + 3
        color: Theme.crust
    }
    Icon {
        visible: root.charging
        anchors.centerIn: body
        name: "bolt"
        filled: true
        size: root.height
        color: Theme.text
    }
}
