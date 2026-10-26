import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    pageId: "printers"

    Label { visible: !Printers.available; color: Theme.error; text: Tr.t("CUPS is off") }
    RowLayout {
        spacing: 10
        Button { icon: "printer"; text: Tr.t("Add"); onClicked: Printers.addPrinter() }
        Button { icon: "refresh"; text: Tr.t("Refresh"); onClicked: Printers.refresh() }
    }
    SettingsSection { text: Printers.list.length === 0 ? Tr.t("None") : Printers.list.length + (Printers.jobs ? " · " + Printers.jobs + Tr.t(" waiting") : "") }
    Repeater {
        model: Printers.list
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 12
            Icon { name: "printer"; size: 16; color: modelData.default ? Theme.accent : Theme.overlay1 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold; text: modelData.name.replace(/_/g, " ") }
                Caption { text: modelData.state + (modelData.default ? Tr.t(" · default") : "") }
            }
            Button { visible: !modelData.default; text: Tr.t("Default"); onClicked: Printers.setDefault(modelData.name) }
            Button { text: Tr.t("Test"); onClicked: Printers.testPage(modelData.name) }
        }
    }
}
