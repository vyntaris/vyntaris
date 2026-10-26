import QtQuick
import QtQuick.Layouts
import qs.config

ListView {
    id: root
    property string current
    property int maxRows: 6
    readonly property real rowHeight: 42
    signal picked(string value)

    Layout.fillWidth: true
    implicitHeight: Math.min(count, maxRows) * rowHeight
    clip: true
    interactive: count > maxRows
    boundsBehavior: Flickable.StopAtBounds

    delegate: PanelSurface {
        id: row
        required property var modelData
        readonly property bool chosen: modelData.value === root.current
        width: root.width
        height: root.rowHeight
        radius: Theme.r(12)
        fill: chosen ? Theme.accent : area.containsMouse ? Theme.alpha(Theme.accent, 0.12) : "transparent"
        Behavior on fill { ColorAnim {} }

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 12
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.weight: row.chosen ? Font.DemiBold : Font.Normal
                color: row.chosen ? Theme.textOnAccent : Theme.text
                text: row.modelData.title
            }
            Label {
                visible: text !== ""
                font.pixelSize: Theme.fontSizeSmall + 1
                color: row.chosen ? Theme.alpha(Theme.textOnAccent, 0.75) : Theme.overlay1
                text: row.modelData.caption ?? ""
            }
            Icon { visible: row.chosen; name: "check"; size: 16; color: Theme.textOnAccent }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.picked(row.modelData.value)
        }
    }
}
