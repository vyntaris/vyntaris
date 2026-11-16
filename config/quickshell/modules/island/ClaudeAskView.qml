import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// A Claude Code session wants to change something: allow it or not, from any session on this desktop.
Item {
    id: root
    readonly property real fullWidth: 560
    readonly property real hang: content.implicitHeight + 26
    readonly property var ask: Claude.ask

    width: fullWidth
    height: Theme.barHeight + hang

    PanelHeader {
        icon: "claude"
        title: Claude.asks.length > 1 ? Tr.f("Claude asks ({0})", Claude.asks.length) : Tr.t("Claude asks")
        HeaderButton {
            visible: !root.ask?.island
            icon: "terminal"
            label: Tr.t("Answer in the terminal")
            onClicked: Claude.answer("terminal")
        }
    }

    PanelBody {
        id: content
        spacing: Theme.space10

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
            Icon { name: root.ask?.icon ?? "claude"; size: 18; color: Theme.accentInk }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    mono: root.ask?.tool === "Bash"
                    font.weight: Font.DemiBold
                    text: root.ask?.what ?? ""
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Theme.subtext0
                    font.pixelSize: Theme.fontSizeSmall
                    text: (root.ask?.tool ?? "") + "  ·  " + (root.ask?.cwd ?? "").replace(Quickshell.env("HOME"), "~")
                }
            }
        }

        PanelSurface {
            Layout.fillWidth: true
            visible: (root.ask?.detail ?? "") !== ""
            implicitHeight: detail.implicitHeight + 16
            radius: Theme.r(10)
            fill: Theme.tint(parent, Theme.crust, 0.45)
            Text {
                id: detail
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 12
                elide: Text.ElideRight
                color: Theme.subtext1
                font { family: Theme.monoFamily; pixelSize: Theme.fontSizeSmall }
                text: root.ask?.detail ?? ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space6
            Button { text: Tr.t("Always, in this session"); onClicked: Claude.answer("always") }
            Item { Layout.fillWidth: true }
            Button { text: Tr.t("Deny"); onClicked: Claude.answer("deny") }
            Button { primary: true; icon: "check"; text: Tr.t("Allow"); onClicked: Claude.answer("allow") }
        }
    }
}
