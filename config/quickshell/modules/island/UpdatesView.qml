import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import "../../components/Slant.js" as Slant
import qs.services

Item {
    id: root
    readonly property real fullWidth: 460
    readonly property real hang: Math.min(list.contentHeight, 260)
        + (deskColumn.visible ? deskColumn.implicitHeight + 14 : 0)
        + (fwColumn.visible ? fwColumn.implicitHeight + 14 : 0)
        + (heldColumn.visible ? heldColumn.implicitHeight + 14 : 0)
        + (Updates.packages.length > 0 ? 104 : Updates.checking || Updates.failed ? 56 : 12)
    function out(y) { return Theme.slanted ? Slant.out(height, Theme.barHeight, y) : 0; }
    readonly property bool active: Panels.updatesOpen

    width: fullWidth
    height: Theme.barHeight + hang

    Component.onCompleted: if (active) activeChanged()
    onActiveChanged: if (active) { Updates.check(); Updates.checkFirmware(); }

    PanelHeader {
        icon: "package-update"
        title: Updates.count > 0 ? Updates.count + Tr.t(" updates") : Updates.firmware.length > 0 ? Tr.t("Firmware")
            : Updates.failed ? Tr.t("Couldn't check") : Tr.t("Up to date")
        HeaderButton {
            icon: "refresh"
            onClicked: { Updates.check(); Updates.checkFirmware(); }
            RotationAnimation on rotation { running: Updates.checking; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
        }
    }

    ListView {
        id: list
        readonly property real widest: root.out(y)
        function lane(row) { return row ? widest - root.out(y + row.y - contentY + row.height) : 0; }
        x: Theme.panelInset - widest
        y: Theme.panelTop
        width: parent.width - 2 * Theme.panelInset + 2 * widest
        height: Math.min(contentHeight, 260)
        clip: true
        model: Updates.packages
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: pkgRow
            required property var modelData
            width: list.width
            height: 26
            RowLayout {
                x: list.lane(pkgRow)
                width: parent.width - 2 * x
                height: parent.height
                spacing: 10
                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall + 1; text: pkgRow.modelData.name }
                Label { visible: pkgRow.modelData.aur; caps: true; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.peach; text: Tr.t("AUR") }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay0; text: pkgRow.modelData.from }
                Icon { name: "chevron-right"; size: 11; color: Theme.overlay0 }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.accent; text: pkgRow.modelData.to }
            }
        }
    }

    ColumnLayout {
        id: deskColumn
        x: 20 - root.out(y + implicitHeight)
        y: list.y + list.height + 10
        width: parent.width - 40 + 2 * root.out(y + implicitHeight)
        visible: Updates.desktop !== null
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Icon { name: "vyntaris"; size: 16; color: Theme.accent }
            Label { Layout.fillWidth: true; caps: true; color: Theme.accent; text: Tr.t("Vyntaris ") + (Updates.desktop?.to ?? "") }
            ChipButton { visible: Updates.held.length === 0; text: Updates.upgrading ? Tr.t("Updating…") : Tr.t("Update"); onClicked: { Panels.updatesOpen = false; Updates.upgrade(); } }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.subtext0
            text: Tr.t("A new version of the desktop, from ") + (Updates.desktop?.from ?? "")
        }
    }

    ColumnLayout {
        id: fwColumn
        x: 20 - root.out(y + implicitHeight)
        y: list.y + list.height + (deskColumn.visible ? deskColumn.implicitHeight + 20 : 10)
        width: parent.width - 40 + 2 * root.out(y + implicitHeight)
        visible: Updates.firmware.length > 0
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Icon { name: "cpu"; size: 16; color: Theme.accent }
            Label { Layout.fillWidth: true; caps: true; color: Theme.accent; text: Tr.t("Firmware") }
            ChipButton { text: Tr.t("Update"); onClicked: { Panels.updatesOpen = false; Updates.upgradeFirmware(); } }
        }
        Repeater {
            model: Updates.firmware
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall + 1; text: modelData.name }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay0; text: modelData.from }
                Icon { name: "chevron-right"; size: 11; color: Theme.overlay0 }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.accent; text: modelData.to }
            }
        }
    }

    ColumnLayout {
        id: heldColumn
        x: 20 - root.out(y + implicitHeight)
        y: list.y + list.height + (deskColumn.visible ? deskColumn.implicitHeight + 10 : 0)
            + (fwColumn.visible ? fwColumn.implicitHeight + 10 : 0) + 10
        width: parent.width - 40 + 2 * root.out(y + implicitHeight)
        visible: Updates.held.length > 0
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Icon { name: "schedule"; size: 16; color: Theme.peach }
            Label { Layout.fillWidth: true; caps: true; color: Theme.peach; text: Tr.t("Waiting for Vyntaris") }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.subtext0
            text: Tr.f("{0} isn't tested with Vyntaris yet. The update waits until it is, usually a day.",
                Updates.held.map(p => p.name + " " + p.to).join(", "))
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.barHeight + 30
        visible: Updates.count === 0 && Updates.checking
        spacing: 8
        Spinner { anchors.verticalCenter: parent.verticalCenter; size: 14 }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            caps: true
            color: Theme.overlay0
            text: Tr.t("Checking…")
        }
    }
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.barHeight + 30
        visible: Updates.count === 0 && Updates.failed && !Updates.checking
        color: Theme.overlay1
        text: Tr.t("No connection to the update servers. It's checked again later.")
    }

    RowLayout {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        spacing: 12

        Button {
            visible: Updates.packages.length > 0
            primary: Updates.held.length === 0
            icon: "arrow-down"
            text: Updates.upgrading ? Tr.t("Updating…") : Updates.held.length > 0 ? Tr.t("Update anyway") : Tr.t("Update now")
            active: !Updates.upgrading
            onClicked: { Panels.updatesOpen = false; Updates.upgrade(); }
        }
        Button {
            visible: Updates.lastResult === "failed" && !Updates.upgrading && Updates.packages.length > 0
            icon: "terminal"
            text: Tr.t("Finish in a terminal")
            onClicked: { Panels.updatesOpen = false; Updates.upgradeInTerminal(); }
        }
    }
}
