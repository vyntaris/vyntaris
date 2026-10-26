import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

SettingsPage {
    id: page
    pageId: "backups"

    SettingsSection { text: Tr.t("Google Drive") }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Icon {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            name: CloudBackup.result === "failed" ? "alert" : CloudBackup.connected ? "check" : "cloud"
            size: 16
            color: CloudBackup.result === "failed" ? Theme.error : CloudBackup.connected ? Theme.accent : Theme.overlay1
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 3
            Label { font.weight: Font.DemiBold; text: !CloudBackup.known ? "" : CloudBackup.connected ? Tr.t("On") : Tr.t("Off") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext0
                text: Tr.t("Your folders copied to your Google Drive. Backing up, taking files back, when it runs and which folders: in Backup.")
            }
            Caption {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: CloudBackup.connected && CloudBackup.last > 0
                color: CloudBackup.result === "failed" ? Theme.error : Theme.overlay1
                text: (CloudBackup.result === "failed" ? Tr.t("Last backup didn't finish · ") : Tr.t("Last backup · "))
                      + new Date(CloudBackup.last * 1000).toLocaleString(Tr.dates, Locale.ShortFormat)
            }
        }
        Button {
            Layout.alignment: Qt.AlignTop
            primary: true
            icon: "cloud"
            text: Tr.t("Open Backup")
            onClicked: Panels.openApp("backup")
        }
    }

    SettingsSection { text: Tr.t("Safe updates") }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Icon {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            name: UpdateGuard.guarded ? "check" : "info"
            size: 16
            color: UpdateGuard.guarded ? Theme.accent : Theme.overlay1
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 3
            Label { font.weight: Font.DemiBold; text: UpdateGuard.guarded ? Tr.t("On") : Tr.t("Off") }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.subtext0
                text: UpdateGuard.guarded
                    ? Tr.t("A snapshot is taken before every update. If Vyntaris can't start after one, it goes back to that snapshot by itself, and the boot menu has an entry for it. Your files aren't part of it.")
                    : Tr.t("Not on this computer: ") + UpdateGuard.reason + Tr.t(". The snapshot before every update is still taken.")
            }
            Caption {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: UpdateGuard.guarded && UpdateGuard.point !== ""
                text: (UpdateGuard.pending ? Tr.t("Last update not started yet · ") : "") + Tr.t("Can go back to ") + UpdateGuard.pointDate
            }
            Caption {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: UpdateGuard.rollback !== null
                color: Theme.accent
                text: Tr.t("An update was undone · ") + UpdateGuard.when(UpdateGuard.rollback?.at ?? "")
            }
        }
        Button {
            id: undoButton
            Layout.alignment: Qt.AlignTop
            property bool asking: false
            visible: UpdateGuard.guarded && UpdateGuard.point !== ""
            icon: "history"
            danger: asking
            text: asking ? Tr.t("Restart and undo") : Tr.t("Undo last update")
            onClicked: {
                if (!asking) { asking = true; stopAsking.restart(); return; }
                asking = false;
                UpdateGuard.undo();
            }
            Timer { id: stopAsking; interval: 5000; onTriggered: undoButton.asking = false }
        }
    }

    SettingsSection { text: Tr.t("Snapshots") }
    RowLayout {
        spacing: 10
        Button { icon: "check"; text: Tr.t("Snapshot"); primary: true; onClicked: Snapshots.create() }
        Button { icon: "refresh"; text: Tr.t("Restore"); onClicked: Snapshots.openTimeshift() }
    }

    Caption { text: Snapshots.list.length + (Snapshots.list.length === 1 ? Tr.t(" snapshot") : Tr.t(" snapshots")) }
    Repeater {
        model: Snapshots.list
        RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 12
            Label { mono: true; font.pixelSize: Theme.fontSizeSmall + 1; text: modelData.date }
            Label { Layout.fillWidth: true; color: Theme.subtext0; elide: Text.ElideRight; text: modelData.comment }
            Caption {
                text: modelData.comment === "before upgrade" ? "upgrade"
                    : modelData.comment === "installed" ? "install"
                    : /O|ondemand/i.test(modelData.tags) ? "manual" : "auto"
            }
        }
    }
}
