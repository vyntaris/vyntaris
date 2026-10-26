import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 340
    readonly property real hang: content.implicitHeight + 24

    width: fullWidth
    height: Theme.barHeight + hang

    PanelHeader { icon: "bolt"; title: Tr.t("NVIDIA GPU") }

    PanelBody {
        id: content
        y: Theme.barHeight + 8

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.subtext0
            text: !Gpu.awake ? Tr.t("Asleep: it uses no power.")
                : Gpu.users.length > 0 ? Tr.t("Awake, and using power, for these apps. It sleeps again once they close.")
                : Tr.t("Awake for a moment: an app checked it as it started. It sleeps again by itself.")
        }

        Repeater {
            model: Gpu.users
            RowLayout {
                id: use
                required property var modelData
                Layout.fillWidth: true
                spacing: 10
                Icon { name: "bolt"; size: 15; color: Theme.green }
                Label { Layout.fillWidth: true; elide: Text.ElideRight; font.weight: Font.DemiBold; text: use.modelData.app }
                ChipButton { danger: true; text: Tr.t("Close"); onClicked: Gpu.close(use.modelData) }
            }
        }
    }
}
