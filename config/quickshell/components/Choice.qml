import QtQuick
import qs.config

Item {
    id: root
    property var options: []
    property var current
    signal picked(var value)

    readonly property int index: options.findIndex(o => o.value === current)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: 32

    PanelSurface {
        anchors.fill: parent
        radius: Theme.r(height / 2)
        fill: Theme.alpha(Theme.crust, 0.45)
        edgeWidth: 1; edge: Theme.glassRim
    }

    PanelSurface {
        readonly property Item target: root.index >= 0 && optionRepeater.count > root.index ? optionRepeater.itemAt(root.index) : null
        visible: target !== null
        x: 3 + (target?.x ?? 0)
        y: 3
        width: target?.width ?? 0
        height: parent.height - 6
        radius: Theme.r(height / 2)
        fill: Theme.accent
        Behavior on x { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
        Behavior on width { Anim { duration: Theme.durationNormal } }
    }

    Row {
        id: row
        x: 3
        height: parent.height

        Repeater {
            id: optionRepeater
            model: root.options
            Item {
                required property var modelData
                required property int index
                width: optLabel.implicitWidth + 24
                height: row.height
                Label {
                    id: optLabel
                    anchors.centerIn: parent
                    font.pixelSize: Theme.fontSizeSmall + 1
                    font.weight: root.index === index ? Font.DemiBold : Font.Normal
                    color: root.index === index ? Theme.textOnAccent : optArea.containsMouse ? Theme.text : Theme.subtext0
                    text: modelData.label
                }
                MouseArea {
                    id: optArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(modelData.value)
                }
            }
        }
    }
}
