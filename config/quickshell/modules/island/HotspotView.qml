import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

// The hotspot: on or off, its name and password, and a QR code phones scan to join.
Item {
    id: root
    readonly property real fullWidth: 560
    readonly property real hang: content.implicitHeight + 26
    readonly property bool active: Panels.hotspotOpen
    readonly property bool changed: nameField.text !== Hotspot.ssid || passField.text !== Hotspot.password

    width: fullWidth
    height: Theme.barHeight + hang

    function load() { nameField.text = Hotspot.ssid; passField.text = Hotspot.password; }
    onActiveChanged: if (active) { Hotspot.refresh(); load(); }
    Component.onCompleted: if (active) activeChanged()
    Connections {
        target: Hotspot
        function onSsidChanged() { if (!nameField.input.activeFocus) nameField.text = Hotspot.ssid; }
        function onPasswordChanged() { if (!passField.input.activeFocus) passField.text = Hotspot.password; }
    }

    PanelHeader {
        icon: "hotspot"
        title: Tr.t("Hotspot")
        HeaderButton { icon: "close"; label: Tr.t("Close"); onClicked: Panels.hotspotOpen = false }
    }

    PanelBody {
        id: content
        spacing: Theme.space12
        Keys.onEscapePressed: Panels.hotspotOpen = false

        Label {
            Layout.fillWidth: true
            visible: !Hotspot.hasCard
            wrapMode: Text.Wrap
            color: Theme.overlay1
            text: Tr.t("This computer has no Wi-Fi card to share from.")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Hotspot.hasCard
            spacing: Theme.space16

            // Scanned with a phone's camera, it joins without typing the password.
            Rectangle {
                id: code
                visible: Hotspot.qr.length > 0
                readonly property int cells: Hotspot.qr.length
                Layout.preferredWidth: 132
                Layout.preferredHeight: 132
                Layout.alignment: Qt.AlignTop
                radius: Theme.r(12)
                color: Theme.text
                Canvas {
                    id: canvas
                    anchors { fill: parent; margins: 10 }
                    property var rows: Hotspot.qr
                    property color ink: Theme.crust
                    onRowsChanged: requestPaint()
                    onInkChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const n = rows.length;
                        if (!n) return;
                        const s = Math.floor(width / n), off = Math.floor((width - s * n) / 2);
                        ctx.fillStyle = ink;
                        for (let y = 0; y < n; y++)
                            for (let x = 0; x < rows[y].length; x++)
                                if (rows[y][x] === "1") ctx.fillRect(off + x * s, off + y * s, s, s);
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    Rectangle {
                        implicitWidth: 10; implicitHeight: 10; radius: 5
                        color: Hotspot.active ? Theme.accent : Theme.overlay0
                    }
                    Label {
                        Layout.fillWidth: true
                        font.weight: Font.DemiBold
                        text: Hotspot.busy ? (Hotspot.active ? Tr.t("Turning off…") : Tr.t("Turning on…"))
                            : !Hotspot.active ? Tr.t("Off")
                            : Hotspot.clients === 1 ? Tr.t("On · 1 device joined")
                            : Tr.f("On · {0} devices joined", Hotspot.clients)
                    }
                }
                Field {
                    id: nameField
                    Layout.fillWidth: true
                    placeholder: Tr.t("Network name")
                    input.Keys.onReturnPressed: passField.input.forceActiveFocus()
                }
                Field {
                    id: passField
                    Layout.fillWidth: true
                    mono: true
                    secret: true; canReveal: true
                    invalid: text !== "" && text.length < 8
                    placeholder: Tr.t("Password (8 or more)")
                    input.Keys.onReturnPressed: if (root.changed && text.length >= 8) Hotspot.change(nameField.text, text)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: Hotspot.hasCard && (Hotspot.viaWifi || Hotspot.failed)
            wrapMode: Text.Wrap
            color: Hotspot.failed ? Theme.error : Theme.subtext0
            font.pixelSize: Theme.fontSizeSmall
            text: Hotspot.failed ? Tr.t("The hotspot couldn't start. The Wi-Fi card may not allow it on this network's channel.")
                : Tr.t("Your internet comes over Wi-Fi, and the card can't share it at the same time: turning this on disconnects it. Plug in a cable, or your phone over USB, to share that.")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Hotspot.hasCard
            spacing: Theme.space6
            Item { Layout.fillWidth: true }
            Button {
                visible: root.changed
                icon: "check"
                active: !Hotspot.busy && nameField.text.trim() !== "" && passField.text.length >= 8
                text: Tr.t("Save")
                onClicked: if (active) Hotspot.change(nameField.text.trim(), passField.text)
            }
            Button {
                primary: true
                icon: "hotspot"
                active: !Hotspot.busy
                text: Hotspot.active ? Tr.t("Turn off") : Hotspot.viaWifi ? Tr.t("Turn on anyway") : Tr.t("Turn on")
                onClicked: if (active) Hotspot.toggle()
            }
        }
    }
}
