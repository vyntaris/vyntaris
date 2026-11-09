import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// After a login in Firefox: save it, or update the saved one.
Item {
    id: root
    readonly property real fullWidth: 520
    readonly property real hang: content.implicitHeight + 26
    readonly property var offer: Passwords.offer

    width: fullWidth
    height: Theme.barHeight + hang

    HoverHandler { onHoveredChanged: Passwords.keepOffer(hovered) }

    PanelHeader {
        icon: "lock"
        title: root.offer?.update ? Tr.t("Update password?") : Tr.t("Save password?")
        HeaderButton { icon: "close"; label: Tr.t("Not now"); onClicked: Passwords.offer = null }
    }

    PanelBody {
        id: content
        spacing: Theme.space12

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space12
            Avatar { size: 36; name: root.offer?.site ?? "" }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    text: root.offer?.site ?? ""
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Theme.subtext0
                    font.pixelSize: Theme.fontSizeSmall
                    text: root.offer?.user || Tr.t("No username")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space6
            Button {
                visible: !root.offer?.update
                text: Tr.t("Never for this site")
                onClicked: Passwords.never()
            }
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Not now"); onClicked: Passwords.offer = null }
            Button {
                primary: true
                icon: "check"
                text: root.offer?.update ? Tr.t("Update") : Tr.t("Save")
                onClicked: Passwords.saveOffer()
            }
        }
    }
}
