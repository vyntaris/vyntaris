import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

SettingsPage {
    pageId: "notifications"

    SettingsRow {
        title: Tr.t("Sounds")
        Switch { checked: Config.theme.sounds; onToggled: on => { Config.theme.sounds = on; Config.saveSoon(); } }
    }
    SettingsRow {
        visible: Config.theme.sounds
        title: Tr.t("Notification sound")
        Choice {
            options: [{ value: "ding", label: Tr.t("Ding") }, { value: "pop", label: Tr.t("Pop") }, { value: "drop", label: Tr.t("Drop") }, { value: "tick", label: Tr.t("Tick") }]
            current: Config.theme.notificationSound
            onPicked: v => {
                Config.theme.notificationSound = v; Config.saveSoon();
                Quickshell.execDetached(["pw-play", Config.notificationSoundPath(v)]);
            }
        }
    }
    SettingsRow {
        title: Tr.t("Stay on screen")
        Choice {
            options: [{ value: 4000, label: Tr.t("4 s") }, { value: 6000, label: Tr.t("6 s") }, { value: 10000, label: Tr.t("10 s") }]
            current: Config.notifications.timeout
            onPicked: v => { Config.notifications.timeout = v; Config.saveSoon(); }
        }
    }
}
