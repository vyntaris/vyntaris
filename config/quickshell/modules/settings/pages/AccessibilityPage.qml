import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

SettingsPage {
    pageId: "access"

    SettingsRow {
        title: Tr.t("High contrast")
        Switch { checked: Config.accessibility.highContrast; onToggled: on => { Config.accessibility.highContrast = on; Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Cursor size")
        Choice {
            options: [{ value: 24, label: Tr.t("Normal") }, { value: 32, label: Tr.t("Large") }, { value: 48, label: Tr.t("Larger") }]
            current: Config.theme.cursorSize
            onPicked: v => { Config.theme.cursorSize = v; Config.saveSoon(); }
        }
    }
}
