import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    pageId: "lock"

    SettingsRow {
        title: Tr.t("Lock now")
        Button { icon: "lock"; text: Tr.t("Lock"); onClicked: Quickshell.execDetached(["loginctl", "lock-session"]) }
    }
    SettingsRow {
        title: Tr.t("Widgets")
        RowLayout {
            spacing: 8
            Button { text: Tr.t("Preview"); onClicked: Panels.inShell("lock", "preview") }
            Switch { checked: Config.lock.widgets; onToggled: on => { Config.lock.widgets = on; Config.saveSoon(); } }
        }
    }
}
