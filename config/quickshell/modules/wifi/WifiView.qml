import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services
import qs.components
import "../../components/Icons.js" as Icons

Item {
    id: root
    required property var device
    property bool open: false
    property bool showHeader: true

    readonly property real fullWidth: 340
    readonly property real hang: content.implicitHeight > 0 ? content.implicitHeight + 28 : 8

    property var pending: null
    property string error: ""

    width: fullWidth
    height: hang

    readonly property var networks: (device?.networks.values ?? [])
        .filter(n => n.name)
        .sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))

    readonly property var connected: networks.find(n => n.connected) ?? null

    function choose(n) {
        error = "";
        if (n.connected || n.stateChanging) return;
        if (n.known || n.security === WifiSecurityType.Open) {
            pending = null;
            n.connect();
        } else {
            pending = n;
            password.text = "";
            password.forceActiveFocus();
        }
    }

    function submitPassword() {
        if (!pending || password.text.length === 0) return;
        pending.connectWithPsk(password.text);
        pending = null;
        password.text = "";
    }

    Binding {
        target: root.device
        property: "scannerEnabled"
        value: root.open
        when: root.device !== null
    }

    onOpenChanged: if (!open) { pending = null; error = ""; }

    PanelBody {
        id: content
        y: root.showHeader ? 14 : 6
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.showHeader
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1000
                    spacing: 2
                    Label { caps: true; text: Tr.t("Wi-Fi"); color: Theme.overlay1 }
                    Label {
                        text: !Networking.wifiEnabled ? Tr.t("Off")
                            : root.networks.find(n => n.connected)?.name ?? Tr.t("Not connected")
                        font.weight: Font.DemiBold
                    }
                }

                Switch {
                    checked: Networking.wifiEnabled
                    onToggled: on => Networking.wifiEnabled = on
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.hairline }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            visible: root.device === null || (Networking.wifiEnabled && root.networks.length === 0)
            caps: true
            text: root.device === null ? Tr.t("No adapter") : Tr.t("Scanning…")
            color: Theme.overlay1
            horizontalAlignment: Text.AlignHCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.showHeader && Networking.wifiEnabled && root.connected !== null
            spacing: 8

            ConnectionSummary {
                Layout.fillWidth: true
                connected: true
                name: root.connected?.name ?? ""
                level: Icons.signal(root.connected?.signalStrength ?? 0)
                detailIcon: root.connected?.security !== WifiSecurityType.Open ? "lock" : ""
                details: (root.connected?.security === WifiSecurityType.Open ? Tr.t("Open") : Tr.t("Secured")) + "  ·  " + (root.device?.name ?? "")
                onDisconnect: root.connected.disconnect()
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; implicitHeight: 1; color: Theme.hairline }
            RowLayout {
                Layout.fillWidth: true
                Caption { Layout.fillWidth: true; text: Tr.t("Nearby") }
                Label {
                    visible: root.networks.filter(n => !n.connected).length === 0
                    caps: true; color: Theme.overlay0; font.pixelSize: Theme.fontSizeSmall - 1; text: Tr.t("Scanning…")
                }
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, 7 * 42)
            visible: Networking.wifiEnabled && model.length > 0
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.showHeader ? root.networks : root.networks.filter(n => !n.connected)

            delegate: Item {
                id: slot
                required property var modelData
                width: list.width
                height: 40
            PanelSurface {
                id: row
                readonly property var modelData: slot.modelData
                readonly property bool busy: modelData.stateChanging
                x: content.lane(slot, list)
                width: slot.width - 2 * x
                height: slot.height
                radius: Theme.r(12)
                fill: row.modelData.connected ? Theme.alpha(Theme.accent, 0.14)
                     : hover.containsMouse ? Theme.hover : "transparent"
                edgeWidth: row.modelData.connected ? 1 : 0; edge: Theme.glassRim
                Behavior on fill { ColorAnim {} }

                Connections {
                    target: row.modelData
                    function onConnectionFailed(reason) {
                        if (reason === ConnectionFailReason.NoSecrets) {
                            root.pending = row.modelData;
                            root.error = Tr.t("Wrong or missing password");
                            password.forceActiveFocus();
                        } else {
                            root.error = "Connection failed: " + ConnectionFailReason.toString(reason);
                        }
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(row.modelData)
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                    spacing: 10

                    Row {
                        id: mini
                        readonly property int lit: Math.max(1, Math.round(Icons.signal(row.modelData.signalStrength) * 5))
                        spacing: 2
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                anchors.bottom: parent.bottom
                                width: 4
                                height: 5 + index * 2.5
                                radius: 1.5
                                color: index < mini.lit ? (row.modelData.connected ? Theme.accent : Theme.text)
                                                        : Theme.alpha(Theme.text, 0.12)
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            elide: Text.ElideRight
                            font.weight: row.modelData.connected ? Font.DemiBold : Font.Normal
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            caps: true
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: row.modelData.connected ? Theme.accent : Theme.overlay1
                            text: row.busy ? (row.modelData.connected ? Tr.t("Disconnecting") : Tr.t("Connecting"))
                                : row.modelData.connected ? Tr.t("Connected")
                                : row.modelData.known ? Tr.t("Saved") : ""
                        }
                    }

                    Icon {
                        visible: row.modelData.security !== WifiSecurityType.Open
                        name: "lock"
                        size: 14
                        color: Theme.overlay1
                    }

                    ChipButton { visible: row.modelData.connected && !row.busy; danger: true; text: Tr.t("Disconnect"); onClicked: row.modelData.disconnect() }
                }
            }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.pending !== null
            spacing: 6

            Label {
                Layout.fillWidth: true
                caps: true
                color: Theme.overlay1
                elide: Text.ElideRight
                text: Tr.t("Password · ") + (root.pending?.name ?? "")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Theme.r(10)
                    color: Theme.alpha(Theme.crust, 0.45)
                    border { width: 1; color: password.activeFocus ? Theme.accent : Theme.glassRim }
                    Behavior on border.color { ColorAnim {} }

                    TextInput {
                        id: password
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.text
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.textOnAccent
                        font { family: Theme.monoFamily; pixelSize: Theme.fontSize }
                        clip: true
                        Keys.onReturnPressed: root.submitPassword()
                        Keys.onEnterPressed: root.submitPassword()
                        Keys.onEscapePressed: root.pending = null
                    }
                }

                Button { primary: true; text: Tr.t("Connect"); onClicked: root.submitPassword() }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            wrapMode: Text.Wrap
            color: Theme.error
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
