import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    pageId: "about"
    spacing: Theme.space10

    SettingsRow { title: Tr.t("System"); Label { color: Theme.subtext0; text: Distro.name } }
    SettingsRow { title: Tr.t("Memory"); Label { mono: true; color: Theme.subtext0; text: SystemStats.formatBytes(SystemStats.memTotal, 0) } }
    SettingsRow { title: Tr.t("Disk"); Label { mono: true; color: Theme.subtext0; text: SystemStats.formatBytes(SystemStats.diskTotal, 0) } }
    SettingsRow { title: Tr.t("Settings file"); Label { mono: true; color: Theme.subtext0; text: Config.path.replace(Quickshell.env("HOME"), "~") } }
    SettingsRow {
        title: Tr.t("Welcome screen")
        Button { text: Tr.t("Open"); onClicked: Panels.settings("welcome") }
    }
}
