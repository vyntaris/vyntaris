import QtQuick
import qs.config

Item {
    id: root
    property real value: 0
    property color fillColor: Theme.accent
    property bool dimmed: false
    property int count: Math.max(8, Math.round(width / 9))
    // From this share of the bar on it shows in the warning colour: the part past what is safe.
    property real caution: 1
    signal moved(real v)

    implicitWidth: 120
    implicitHeight: 16

    readonly property real shown: Math.max(0, Math.min(1, area.pressed ? area.dragValue : value))
    readonly property int lit: Math.round(shown * count)

    Row {
        id: cells
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Repeater {
            model: root.count
            Rectangle {
                required property int index
                readonly property bool on: index < root.lit
                width: (root.width - (root.count - 1) * cells.spacing) / root.count
                height: on ? 12 : 6
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: !on ? Theme.alpha(Theme.text, area.containsMouse ? 0.16 : 0.1)
                    : root.dimmed ? Theme.overlay0
                    : index >= Math.round(root.caution * root.count) ? Theme.warning
                    : index === root.lit - 1 ? Theme.accentBright : root.fillColor
                Behavior on height { Anim { duration: Theme.durationFast } }
                Behavior on color { ColorAnim {} }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        property real dragValue: 0

        function update(mouse) {
            dragValue = Math.max(0, Math.min(1, mouse.x / root.width));
            root.moved(dragValue);
        }
        onPressed: mouse => update(mouse)
        onPositionChanged: mouse => { if (pressed) update(mouse); }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
