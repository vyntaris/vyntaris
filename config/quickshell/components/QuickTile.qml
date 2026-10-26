import QtQuick
import QtQuick.Layouts
import qs.config

TileSurface {
    id: root
    property string icon
    property string title
    property string subtitle
    property bool on: false
    property bool more: false
    signal clicked()
    signal moreClicked()

    implicitHeight: 58
    radius: Theme.r(18)
    opacity: enabled ? 1 : 0.45
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onActivated: mouse => mouse.button === Qt.RightButton && root.more ? root.moreClicked() : root.clicked()

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: root.more ? 4 : 14 }
        spacing: 10

        Rectangle {
            implicitWidth: 38
            implicitHeight: 38
            radius: 19
            color: root.on ? Theme.accent : Theme.alpha(Theme.text, 0.08)
            Behavior on color { ColorAnim {} }
            Icon { anchors.centerIn: parent; name: root.icon; size: 18; color: root.on ? Theme.textOnAccent : Theme.subtext1 }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.weight: Font.DemiBold
                text: root.title
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                color: root.on ? Theme.subtext1 : Theme.overlay1
                text: root.subtitle
            }
        }
        Rectangle {
            visible: root.more
            implicitWidth: 32
            implicitHeight: 42
            radius: Theme.r(13)
            color: moreArea.containsMouse ? Theme.alpha(Theme.text, 0.1) : "transparent"
            Behavior on color { ColorAnim {} }
            Icon { anchors.centerIn: parent; name: "chevron-right"; size: 14; color: root.on ? Theme.subtext1 : Theme.overlay1 }
            MouseArea {
                id: moreArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.moreClicked()
            }
        }
    }
}
