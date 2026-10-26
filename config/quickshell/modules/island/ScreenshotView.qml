import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import "../../components/Slant.js" as Slant
import qs.services

Item {
    id: root
    readonly property real fullWidth: 570
    readonly property real hang: 112
    function out(y) { return Theme.slanted ? Slant.out(height, Theme.barHeight, y) : 0; }

    width: fullWidth
    height: Theme.barHeight + hang

    HoverHandler { onHoveredChanged: Screenshot.keepOpen(hovered) }

    PanelHeader {
        icon: "image"
        title: Tr.t("Screenshot")
        Icon { name: "check"; size: 13; stroke: 2.2; color: Theme.success }
        Label { caps: true; color: Theme.success; text: Tr.t("Copied") }
        Rectangle {
            implicitWidth: 20
            implicitHeight: 20
            radius: 10
            color: closeArea.containsMouse ? Theme.alpha(Theme.error, 0.2) : Theme.alpha(Theme.text, 0.07)
            Icon { anchors.centerIn: parent; name: "close"; size: 10; stroke: 2.2; color: closeArea.containsMouse ? Theme.error : Theme.subtext0 }
            MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Screenshot.dismiss() }
        }
    }

    RowLayout {
        x: 20 - root.out(y + height)
        y: Theme.barHeight + 4
        width: parent.width - 40 + 2 * root.out(y + height)
        spacing: 14

        ClippingRectangle {
            implicitWidth: 152
            implicitHeight: 86
            radius: Theme.r(12)
            color: Theme.alpha(Theme.text, 0.06)
            border { width: 1; color: Theme.glassRim }
            Image {
                anchors.fill: parent
                source: Screenshot.lastPath ? "file://" + Screenshot.lastPath : ""
                sourceSize: Qt.size(304, 172)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Screenshot.open() }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Field {
                id: nameField
                Layout.fillWidth: true
                implicitHeight: 30
                mono: true
                text: Screenshot.lastPath.split("/").pop().replace(/\.png$/i, "")
                onCommitted: t => Screenshot.rename(t)
                onActiveFocusChanged: Screenshot.keepOpen(activeFocus)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Button { Layout.fillWidth: true; Layout.preferredWidth: 1; icon: "image"; text: Tr.t("Edit"); onClicked: Screenshot.editShot() }
                Button { Layout.fillWidth: true; Layout.preferredWidth: 1; icon: "external"; text: Tr.t("Open"); onClicked: Screenshot.open() }
                Button { Layout.fillWidth: true; Layout.preferredWidth: 1; icon: "folder"; text: Tr.t("Folder"); onClicked: Screenshot.openFolder() }
                Button { Layout.fillWidth: true; Layout.preferredWidth: 1; icon: "trash"; text: Tr.t("Delete"); danger: true; onClicked: Screenshot.remove() }
            }
        }
    }
}
