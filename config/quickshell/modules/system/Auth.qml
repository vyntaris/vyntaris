import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Scope {
    id: root

    PolkitAgent { id: agent }

    readonly property var flow: agent.flow
    readonly property bool open: agent.isActive && flow !== null
    property bool showPassword: false

    function submit() {
        if (!flow?.isResponseRequired || !field.text) return;
        flow.submit(field.text);
        field.text = "";
    }
    function cancel() {
        field.text = "";
        flow?.cancelAuthenticationRequest();
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() { shake.restart(); }
        function onIsResponseRequiredChanged() { if (root.flow?.isResponseRequired) focusTimer.restart(); }
    }
    onOpenChanged: {
        showPassword = false;
        if (open) focusTimer.restart(); else field.text = "";
    }

    PanelWindow {
        id: win
        visible: root.open
        screen: Quickshell.screens.find(s => s.name === Monitors.focused?.name) ?? Quickshell.screens[0]
        WlrLayershell.namespace: "quickshell-auth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        ScreencopyView {
            id: shot
            anchors.fill: parent
            captureSource: root.open ? win.screen : null
            live: false
            visible: false
        }
        Item {
            anchors.fill: parent
            opacity: root.open && shot.hasContent ? 1 : 0
            Behavior on opacity { Anim {} }
            MultiEffect {
                anchors.fill: parent
                source: shot
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                blurMultiplier: 0.6
            }
            Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.base, 0.32) }
        }
        MouseArea { anchors.fill: parent }

        Rectangle {
            id: card
            visible: shot.hasContent
            anchors.centerIn: parent
            width: 420
            height: body.implicitHeight + 48
            radius: Theme.r(30)
            border { width: 1; color: root.flow?.failed ? Theme.alpha(Theme.error, 0.6) : Theme.glassEdge }
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.alpha(Theme.isDark ? Theme.crust : Theme.base, 0.78) }
                GradientStop { position: 1; color: Theme.alpha(Theme.isDark ? Theme.crust : Theme.base, 0.7) }
            }
            Rectangle { x: parent.radius + 6; width: 22; height: 2; radius: 1; color: Theme.accent }
            transform: Translate { id: shakeShift }
            scale: root.open ? 1 : 0.94
            Behavior on scale { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }

            SequentialAnimation {
                id: shake
                Anim { target: shakeShift; property: "x"; to: -10; duration: 50 }
                Anim { target: shakeShift; property: "x"; to: 10; duration: 70 }
                Anim { target: shakeShift; property: "x"; to: -6; duration: 70 }
                Anim { target: shakeShift; property: "x"; to: 0; duration: 60 }
            }

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 14

                RowLayout {
                    spacing: 12
                    Rectangle {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: 22
                        color: Theme.alpha(Theme.accent, 0.18)
                        border { width: 1; color: Theme.alpha(Theme.accent, 0.55) }
                        Icon { anchors.centerIn: parent; name: "lock"; size: 18; color: Theme.accent }
                    }
                    ColumnLayout {
                        spacing: 2
                        Label { caps: true; color: Theme.accent; text: Tr.t("Authentication required") }
                        Label { color: Theme.subtext0; font.pixelSize: Theme.fontSizeSmall; text: Quickshell.env("USER") || "" }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.flow?.message ?? ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Field {
                        id: field
                        Layout.fillWidth: true
                        secret: !(root.showPassword || (root.flow?.responseVisible ?? false))
                        enabled: root.flow?.isResponseRequired ?? false
                        placeholder: Tr.t("Password")
                        Keys.onEscapePressed: root.cancel()
                        Connections { target: field.input; function onAccepted() { root.submit(); } }
                    }
                    IconButton {
                        icon: root.showPassword ? "eye-off" : "eye"
                        on: root.showPassword
                        onClicked: { root.showPassword = !root.showPassword; field.input.forceActiveFocus(); }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.flow?.failed || root.flow?.supplementaryIsError ? Theme.error : Theme.subtext0
                    text: root.flow?.failed ? Tr.t("Wrong password") : (root.flow?.supplementaryMessage ?? "")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Button { text: Tr.t("Cancel"); onClicked: root.cancel() }
                    Button { primary: true; text: Tr.t("Authenticate"); active: field.text !== ""; onClicked: root.submit() }
                }
            }
        }
    }

    Timer { id: focusTimer; interval: 30; onTriggered: field.input.forceActiveFocus() }
}
