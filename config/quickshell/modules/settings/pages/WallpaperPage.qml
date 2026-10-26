import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    pageId: "wallpaper"

    SettingsRow {
        title: Tr.t("Wallpaper")
        Button { icon: "image"; text: Tr.t("Open"); onClicked: Panels.wallpaperOpen = true }
    }
    SettingsRow {
        title: Tr.t("Folder")
        Field { implicitWidth: 300; mono: true; text: Config.wallpaper.directory; onCommitted: t => { Config.wallpaper.directory = t.trim(); Config.saveSoon(); } }
    }
    SettingsRow {
        title: Tr.t("Fit")
        Choice {
            options: [{ value: "crop", label: Tr.t("Fill") }, { value: "fit", label: Tr.t("Fit") }, { value: "stretch", label: Tr.t("Stretch") }]
            current: Config.wallpaper.fillMode
            onPicked: v => { Config.wallpaper.fillMode = v; Config.saveSoon(); }
        }
    }
}
