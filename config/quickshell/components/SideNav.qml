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
    signal picked(string id)

    readonly property real needed: 24 + header.implicitHeight + 12 + 4 + searchField.implicitHeight + 8 + 4 + navColumn.implicitHeight

    Layout.fillHeight: true
    Layout.preferredWidth: Theme.navWidth
    color: Theme.mantle

    ColumnLayout {
        anchors { fill: parent; margins: Theme.navInset }
        spacing: Theme.space4

        RowLayout {
            id: header
            Layout.bottomMargin: Theme.space12
            Layout.leftMargin: Theme.space6
            spacing: Theme.space10
            Icon { name: root.icon; size: 22; color: Theme.accentInk }
            ColumnLayout {
                spacing: 0
                Label { font.weight: Font.Bold; text: root.title }
                Caption { text: root.subtitle }
            }
        }

        Field {
            id: searchField
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.space8
        }

        Flickable {
            id: navScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: navColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: navColumn
                width: parent.width
                spacing: Theme.navItemGap
                Repeater {
                    model: root.pages
                    Rectangle {
                        id: item
                        required property var modelData
                        readonly property bool current: root.current === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: Theme.navItemHeight
                        radius: Theme.navRadius
                        color: current ? Theme.accent : navArea.containsMouse ? Theme.hover : "transparent"
                        Behavior on color { ColorAnim {} }
                        RowLayout {
                            anchors { fill: parent; leftMargin: Theme.space12; rightMargin: Theme.space12 }
                            spacing: Theme.space10
                            Icon { name: item.modelData.icon; size: 16; filled: item.current; color: item.current ? Theme.textOnAccent : Theme.overlay1 }
                            Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: item.current ? Font.DemiBold : Font.Normal; color: item.current ? Theme.textOnAccent : Theme.subtext0; text: Tr.t(item.modelData.label) }
                        }
                        PressArea {
                            id: navArea
                            anchors.fill: parent
                            label: Tr.t(item.modelData.label)
                            role: Accessible.RadioButton
                            checked: item.current
                            onActiveFocusChanged: {
                                if (!activeFocus) return;
                                if (item.y < navScroll.contentY) navScroll.contentY = item.y;
                                else if (item.y + item.height > navScroll.contentY + navScroll.height) navScroll.contentY = item.y + item.height - navScroll.height;
                            }
                            onClicked: root.picked(item.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
