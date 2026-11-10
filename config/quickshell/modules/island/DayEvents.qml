import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// Under the month: the picked day's events. A click opens the calendar on that day.
ColumnLayout {
    id: root
    property date day: new Date()
    readonly property var list: Calendar.on(day)
    visible: list.length > 0
    spacing: Theme.space2

    function openDay() {
        Panels.closeAll();
        Panels.openApp("calendar", "open", Calendar.key(root.day));
    }

    Repeater {
        model: root.list
        PanelSurface {
            id: row
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Theme.r(8)
            fill: area.containsMouse ? Theme.hoverOn(parent) : "transparent"
            RowLayout {
                anchors { fill: parent; leftMargin: Theme.space6; rightMargin: Theme.space8 }
                spacing: Theme.space10
                Rectangle {
                    Layout.preferredWidth: 3
                    Layout.preferredHeight: 18
                    radius: 2
                    color: row.modelData.google ? Theme.accent : Theme.overlay1
                }
                Label {
                    Layout.preferredWidth: Theme.fontSize * 3.6
                    mono: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.subtext0
                    text: row.modelData.allDay ? Tr.t("All day") : row.modelData.start.slice(11, 16)
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.modelData.title
                }
                Icon {
                    visible: row.modelData.remind >= 0
                    name: "bell"
                    size: 12
                    color: Theme.overlay1
                }
            }
            MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openDay() }
        }
    }
}
