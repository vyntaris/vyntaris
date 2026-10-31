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
        title: Tr.t("Text size")
        Choice {
            options: [{ value: 12, label: Tr.t("Small") }, { value: 13, label: Tr.t("Normal") }, { value: 15, label: Tr.t("Large") }, { value: 17, label: Tr.t("Larger") }]
            current: Config.theme.fontSize
            onPicked: v => { Config.theme.fontSize = v; Config.saveSoon(); }
        }
    }
    Label {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.overlay1
        text: Tr.t("For everything twice the size, set the scale to 2 under Displays.")
    }
    SettingsRow {
        title: Tr.t("Animations")
        Choice {
            options: [{ value: 0, label: Tr.t("Off") }, { value: 1, label: Tr.t("Normal") }, { value: 1.5, label: Tr.t("Quick") }]
            current: Config.theme.animationSpeed
            onPicked: v => { Config.theme.animationSpeed = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        title: Tr.t("Volume above 100%")
        Switch { checked: Config.audio.boost; onToggled: on => { Config.audio.boost = on; Config.saveSoon(); } }
    }
    Label {
        Layout.fillWidth: true
        visible: Config.audio.boost
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.overlay1
        text: Tr.t("The volume goes up to 150%. Above 100% sound can distort, and very loud sound can harm your hearing and speakers.")
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
