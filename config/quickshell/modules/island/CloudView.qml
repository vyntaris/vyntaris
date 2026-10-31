import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 440
    readonly property real hang: content.implicitHeight + 26
    readonly property bool busy: CloudBackup.backingUp || CloudBackup.signingIn || CloudBackup.running

    width: fullWidth
    height: Theme.barHeight + hang

    Connections {
        target: Panels
        function onCloudOpenChanged() { if (Panels.cloudOpen) CloudBackup.refresh(); }
    }

    PanelHeader {
        icon: "cloud"
        title: Tr.t("Google Drive")
        Label {
            visible: CloudBackup.backingUp
            overline: true
            color: Theme.overlay1
            font.family: Theme.monoFamily
            text: Math.round(CloudBackup.progress * 100) + "%"
        }
    }

    PanelBody {
        id: content
        spacing: Theme.space12

        Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            readonly property bool none: !CloudBackup.signingIn && !CloudBackup.backingUp && !root.busy && CloudBackup.last <= 0
            font.weight: none ? Font.Normal : Font.DemiBold
            color: none ? Theme.overlay1 : Theme.text
            text: CloudBackup.signingIn ? Tr.t("Signing in…")
                : CloudBackup.backingUp ? Tr.f("Backing up · {0}", CloudBackup.folder)
                : root.busy ? Tr.t("Backing up now…")
                : CloudBackup.last > 0 ? (CloudBackup.result === "failed" ? Tr.t("Last backup didn't finish · ") : Tr.t("Last backup · "))
                    + new Date(CloudBackup.last * 1000).toLocaleString(Tr.dates, Locale.ShortFormat)
                : Tr.t("No backup yet")
        }
        Progress {
            Layout.fillWidth: true
            visible: CloudBackup.backingUp
            value: CloudBackup.progress
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8
            Button {
                visible: root.busy
                danger: true
                icon: "stop"
                text: Tr.t("Stop backup")
                onClicked: CloudBackup.stop()
            }
            Button {
                visible: !root.busy && CloudBackup.connected
                primary: true
                icon: "refresh"
                text: Tr.t("Back up now")
                onClicked: CloudBackup.backUpNow()
            }
            Item { Layout.fillWidth: true }
            Button {
                text: Tr.t("Open Backup")
                onClicked: { Panels.cloudOpen = false; Panels.openApp("backup"); }
            }
        }
    }
}
