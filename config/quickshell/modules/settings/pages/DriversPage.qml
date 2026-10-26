import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    id: page
    pageId: "drivers"

    onVisibleChanged: if (visible) Drivers.survey()
    Component.onCompleted: if (visible) Drivers.survey()

    function icon(kind) {
        return { "Graphics": "monitor", "Wi-Fi": "wifi", "Sound": "volume", "Processor": "cpu",
                 "Printer": "printer", "Scanner": "image", "Virtual machine": "windows" }[kind] ?? "settings";
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1000
            spacing: 2
            Label {
                font.pixelSize: Theme.fontSize + 3
                font.weight: Font.DemiBold
                text: Drivers.installing ? Tr.t("Installing…")
                    : Drivers.surveying && Drivers.devices.length === 0 ? Tr.t("Looking at the hardware…")
                    : Drivers.missing.length === 0 ? Tr.t("Every driver is installed")
                    : Drivers.missing.length === 1 ? Tr.t("One driver to install") : Drivers.missing.length + Tr.t(" drivers to install")
            }
            Caption { text: Tr.t("Installed by themselves, also for a printer or a scanner plugged in later") }
        }
        Button {
            visible: Drivers.missing.length > 0
            primary: true
            icon: "download"
            text: Tr.t("Install")
            active: !Drivers.installing
            onClicked: Drivers.install()
        }
    }
    Label {
        visible: Drivers.failure !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.error
        text: Drivers.failure
    }

    SettingsSection { text: Tr.t("This computer") }
    Repeater {
        model: Drivers.devices
        RowLayout {
            id: row
            required property var modelData
            readonly property bool ready: modelData.missing.length === 0 && modelData.unavailable.length === 0
            Layout.fillWidth: true
            spacing: 12
            Icon {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 2
                name: page.icon(row.modelData.kind)
                size: 16
                color: row.ready ? Theme.accent : Theme.warning
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.weight: Font.DemiBold; text: row.modelData.name }
                Caption {
                    text: row.modelData.kind + " · "
                        + (row.ready ? "ready"
                           : row.modelData.missing.length ? Tr.t("needs ") + row.modelData.missing.join(", ")
                           : Tr.t("not in the repositories: ") + row.modelData.unavailable.join(", "))
                }
                Label {
                    visible: row.modelData.note !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Theme.subtext0
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: row.modelData.note
                }
            }
        }
    }
}
