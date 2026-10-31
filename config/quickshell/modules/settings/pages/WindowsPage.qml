import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

SettingsPage {
    pageId: "windows"

    SettingsRow {
        title: Tr.t("Rounding")
        Choice {
            enabled: Config.bar.corners !== "square" && Config.bar.inside !== "sharp"
            opacity: enabled ? 1 : Theme.disabledOpacity
            options: [{ value: 0, label: Tr.t("None") }, { value: 10, label: Tr.t("Normal") }, { value: 16, label: Tr.t("Large") }]
            current: Config.windows.rounding
            onPicked: v => { Config.windows.rounding = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        title: Tr.t("Outer gaps")
        Choice {
            options: [{ value: 0, label: Tr.t("None") }, { value: 8, label: Tr.t("Normal") }, { value: 14, label: Tr.t("Large") }]
            current: Config.bar.windowGap
            onPicked: v => { Config.bar.windowGap = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        title: Tr.t("Inner gaps")
        Choice {
            options: [{ value: 0, label: Tr.t("None") }, { value: 5, label: Tr.t("Normal") }, { value: 9, label: Tr.t("Large") }]
            current: Config.windows.gapsIn
            onPicked: v => { Config.windows.gapsIn = v; Config.saveSoon(); }
        }
    }
    SettingsRow {
        title: Tr.t("Border")
        Choice {
            options: [{ value: 0, label: Tr.t("None") }, { value: 1, label: Tr.t("Thin") }, { value: 2, label: Tr.t("Normal") }]
            current: Config.windows.border
            onPicked: v => { Config.windows.border = v; Config.saveSoon(); }
        }
    }
}
