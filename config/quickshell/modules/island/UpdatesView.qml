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
        title: Updates.count === 1 ? Tr.t("1 update") : Updates.count > 1 ? Tr.f("{0} updates", Updates.count) : Updates.firmware.length > 0 ? Tr.t("Firmware")
            : Updates.failed ? Tr.t("Couldn't check") : Tr.t("Up to date")
        HeaderButton {
            icon: "refresh"
            label: Tr.t("Check again")
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
        model: Updates.desktop ? Updates.packages.filter(p => p.name !== "vyntaris") : Updates.packages
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
                spacing: Theme.space10
                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeLabel; text: pkgRow.modelData.name }
                Label { visible: pkgRow.modelData.aur; overline: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay1; text: Tr.t("AUR") }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay0; text: pkgRow.modelData.from }
                Icon { name: "chevron-right"; size: 11; color: Theme.overlay0 }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.accentInk; text: pkgRow.modelData.to }
            }
        }
    }

    ColumnLayout {
        id: deskColumn
        x: 20 - root.out(y + implicitHeight)
        y: list.y + list.height + 10
        width: parent.width - 40 + 2 * root.out(y + implicitHeight)
        visible: Updates.desktop !== null
        spacing: Theme.space6

        RowLayout {
            Layout.fillWidth: true
            Icon { name: "vyntaris"; size: 16; color: Theme.accentInk }
            Label { Layout.fillWidth: true; overline: true; color: Theme.accentInk; text: Tr.f("Vyntaris {0}", Updates.desktop?.to ?? "") }
            ChipButton { visible: Updates.held.length === 0 && Updates.packages.length === 0; text: Updates.upgrading ? Tr.t("Updating…") : Tr.t("Update"); onClicked: { Panels.updatesOpen = false; Updates.upgrade(); } }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.subtext0
            text: Tr.f("A new version of the desktop, from {0}", Updates.desktop?.from ?? "")
        }
    }

    ColumnLayout {
        id: fwColumn
        x: 20 - root.out(y + implicitHeight)
        y: list.y + list.height + (deskColumn.visible ? deskColumn.implicitHeight + 20 : 10)
        width: parent.width - 40 + 2 * root.out(y + implicitHeight)
        visible: Updates.firmware.length > 0
        spacing: Theme.space6
        RowLayout {
            Layout.fillWidth: true
            Icon { name: "cpu"; size: 16; color: Theme.accentInk }
            Label { Layout.fillWidth: true; overline: true; color: Theme.accentInk; text: Tr.t("Firmware") }
            ChipButton { text: Tr.t("Update"); onClicked: { Panels.updatesOpen = false; Updates.upgradeFirmware(); } }
        }
        Repeater {
            model: Updates.firmware
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.space10
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeLabel; text: modelData.name }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay0; text: modelData.from }
                Icon { name: "chevron-right"; size: 11; color: Theme.overlay0 }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.accentInk; text: modelData.to }
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
        spacing: Theme.space6
        RowLayout {
            Layout.fillWidth: true
            Icon { name: "schedule"; size: 16; color: Theme.accentInk }
            Label { Layout.fillWidth: true; overline: true; color: Theme.accentInk; text: Tr.t("Waiting for Vyntaris") }
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
        spacing: Theme.space8
        Spinner { anchors.verticalCenter: parent.verticalCenter; size: 14 }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.overlay1
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
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.space16 }
        spacing: Theme.space12

        Button {
            visible: Updates.packages.length > 0
            primary: Updates.held.length === 0
            icon: "arrow-down"
            text: Updates.upgrading ? Tr.t("Updating…") : Updates.held.length > 0 ? Tr.t("Update anyway") : Tr.t("Update now")
            busy: Updates.upgrading
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
