import QtQuick
import qs.config

Item {
    id: root
    property var values: []
    property int count: values.length
    property color color: Theme.accent
    property real gap: 2
    property real minimum: 0.08

    Row {
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.count
            Item {
                required property int index
                width: root.count > 0 ? (root.width - (root.count - 1) * root.gap) / root.count : 0
                height: root.height
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Math.max(width, parent.height * Math.max(root.minimum, Math.min(1, root.values[index] ?? 0)))
                    radius: width / 2
                    color: root.color
                }
            }
        }
    }
}
