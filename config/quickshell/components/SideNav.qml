import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root
    property string icon
    property string title
    property string subtitle
    property alias search: searchField
    property alias searchHint: searchField.placeholder
    property var pages: []
    property string current
    property int itemHeight: 27
    property int itemSpacing: 2
    signal picked(string id)

    readonly property real needed: 24 + header.implicitHeight + 12 + 4 + searchField.implicitHeight + 8 + 4 + navColumn.implicitHeight

    Layout.fillHeight: true
    Layout.preferredWidth: 206
    color: Theme.mantle

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 4

        RowLayout {
            id: header
            Layout.bottomMargin: 12
            Layout.leftMargin: 6
            spacing: 10
            Icon { name: root.icon; size: 22; color: Theme.accent }
            ColumnLayout {
                spacing: 0
                Label { font.weight: Font.Bold; text: root.title }
                Caption { text: root.subtitle }
            }
        }

        Field {
            id: searchField
            Layout.fillWidth: true
            Layout.bottomMargin: 8
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: navColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: navColumn
                width: parent.width
                spacing: root.itemSpacing
                Repeater {
                    model: root.pages
                    Rectangle {
                        id: item
                        required property var modelData
                        readonly property bool current: root.current === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: root.itemHeight
                        radius: Theme.r(9)
                        color: current ? Theme.accent : navArea.containsMouse ? Theme.hover : "transparent"
                        Behavior on color { ColorAnim {} }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 11 }
                            spacing: 9
                            Icon { name: item.modelData.icon; size: 15; filled: item.current; color: item.current ? Theme.textOnAccent : Theme.overlay1 }
                            Label { Layout.fillWidth: true; color: item.current ? Theme.textOnAccent : Theme.subtext0; text: Tr.t(item.modelData.label) }
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.picked(item.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
