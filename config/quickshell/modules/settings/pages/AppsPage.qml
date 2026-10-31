import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

SettingsPage {
    pageId: "apps"

    SettingsRow { title: Tr.t("Terminal"); Field { mono: true; text: Config.apps.terminal; onCommitted: t => { Config.apps.terminal = t.trim(); Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Run in terminal"); Field { mono: true; text: Config.apps.terminalRun; onCommitted: t => { Config.apps.terminalRun = t.trim(); Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Browser"); Field { mono: true; text: Config.apps.browser; onCommitted: t => { Config.apps.browser = t.trim(); Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("File manager"); Field { mono: true; text: Config.apps.fileManager; onCommitted: t => { Config.apps.fileManager = t.trim(); Config.saveSoon(); } } }
    SettingsRow { title: Tr.t("Editor"); Field { mono: true; text: Config.apps.editor; onCommitted: t => { Config.apps.editor = t.trim(); Config.saveSoon(); } } }

    SettingsSection { text: Tr.t("Store") }
    SettingsRow {
        title: Tr.t("Apps from the AUR")
        Switch { checked: Config.apps.aur; onToggled: on => { Config.apps.aur = on; Config.saveSoon(); } }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Theme.subtext0
        font.pixelSize: Theme.fontSizeLabel
        text: Tr.t("The AUR holds recipes anyone can upload, and Arch doesn't check them: one could install something harmful. The Store shows each one's votes and when it last changed, and asks before it builds one.")
    }
}
