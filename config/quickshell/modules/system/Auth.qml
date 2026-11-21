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

    LazyLoader {
        id: agentLoader
        active: true
        PolkitAgent {}
    }
    readonly property var agent: agentLoader.item

    Timer {
        interval: 5000
        repeat: true
        running: !(root.agent?.isRegistered ?? false) && !root.open
        onTriggered: { agentLoader.active = false; agentLoader.active = true; }
    }

    readonly property var flow: agent?.flow ?? null
    readonly property bool open: (agent?.isActive ?? false) && flow !== null
    property bool showPassword: false

    // Without Enter, as on the lock screen: when typing stops for a moment a hidden password is checked quietly, and
    // a wrong one shows nothing. Each check is a try for the lockout, so not for a few letters or twice for the same.
    readonly property bool checkWhenPaused: Config.lock.autoUnlock && !(flow?.responseVisible ?? false)
    property bool quiet: false
    property string checked: ""

    function submit() {
        if (!flow?.isResponseRequired || !field.text) return;
        quiet = false;
        flow.submit(field.text);
        field.text = "";
    }
    function submitQuietly() {
        if (!checkWhenPaused || !flow?.isResponseRequired || field.text.length < 4 || field.text === checked) return;
        checked = field.text;
        quiet = true;
        flow.submit(field.text);
    }
    Timer { id: pause; interval: 600; onTriggered: root.submitQuietly() }
    function cancel() {
        field.text = "";
        flow?.cancelAuthenticationRequest();
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() { if (!root.quiet) shake.restart(); }
        // Ready for another: typing went on during a quiet check, so check what's there now.
        function onIsResponseRequiredChanged() { if (root.flow?.isResponseRequired) { focusTimer.restart(); if (root.quiet) pause.restart(); } }
    }
    onOpenChanged: {
        showPassword = false;
        quiet = false;
        checked = "";
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
            radius: Theme.r(20)
            border { width: 1; color: root.flow?.failed && !root.quiet ? Theme.tint(parent, Theme.error, 0.6) : Theme.edgeOn(parent) }
            color: Theme.isDark ? Theme.crust : Theme.base
            transform: Translate { id: shakeShift }
            scale: root.open ? 1 : 0.94
            Behavior on scale { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }

            SequentialAnimation {
                id: shake
                Anim { target: shakeShift; property: "x"; to: -10; duration: Theme.paced(50) }
                Anim { target: shakeShift; property: "x"; to: 10; duration: Theme.paced(70) }
                Anim { target: shakeShift; property: "x"; to: -6; duration: Theme.paced(70) }
                Anim { target: shakeShift; property: "x"; to: 0; duration: Theme.paced(60) }
            }

            ColumnLayout {
                id: body
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space24 }
                spacing: Theme.space14

                RowLayout {
                    spacing: Theme.space12
                    Rectangle {
                        implicitWidth: 44
                        implicitHeight: 44
                        radius: 22
                        color: Theme.accent
                        Icon { anchors.centerIn: parent; name: "lock"; size: 18; color: Theme.textOnAccent }
                    }
                    ColumnLayout {
                        spacing: Theme.space2
                        Label { overline: true; color: Theme.accentInk; text: Tr.t("Authentication required") }
                        // Whose password polkit asks for: the chosen identity, not necessarily who is signed in.
                        Label {
                            color: Theme.subtext0
                            font.pixelSize: Theme.fontSizeSmall
                            text: root.flow?.selectedIdentity?.displayName || Quickshell.env("USER") || ""
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.flow?.message ?? ""
                }

                // More than one may answer (several admins): the password is that of the one picked here.
                Choice {
                    visible: (root.flow?.identities?.length ?? 0) > 1
                    options: (root.flow?.identities ?? []).map((id, i) => ({ value: i, label: id.displayName }))
                    current: (root.flow?.identities ?? []).indexOf(root.flow?.selectedIdentity)
                    onPicked: v => { root.flow.selectedIdentity = root.flow.identities[v]; field.text = ""; }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    PasswordCells {
                        id: field
                        Layout.fillWidth: true
                        wrong: (root.flow?.failed ?? false) && field.text === "" && !root.quiet
                        reveal: root.showPassword || (root.flow?.responseVisible ?? false)
                        // Open to typing during a quiet check too.
                        enabled: (root.flow?.isResponseRequired ?? false) || root.quiet
                        Keys.onEscapePressed: root.cancel()
                        onSubmitted: root.submit()
                        onTextChanged: if (root.checkWhenPaused) pause.restart()
                    }
                    IconButton {
                        icon: root.showPassword ? "eye-off" : "eye"
                        label: root.showPassword ? Tr.t("Hide password") : Tr.t("Show password")
                        on: root.showPassword
                        onClicked: { root.showPassword = !root.showPassword; field.input.forceActiveFocus(); }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    readonly property bool wrongShown: (root.flow?.failed ?? false) && !root.quiet
                    color: wrongShown || root.flow?.supplementaryIsError ? Theme.error : Theme.subtext0
                    text: wrongShown ? Tr.t("Wrong password") : (root.flow?.supplementaryMessage ?? "")
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space2
                    spacing: Theme.space8
                    Item { Layout.fillWidth: true }
                    Button { radius: Theme.r(12); text: Tr.t("Cancel"); onClicked: root.cancel() }
                    Button { radius: Theme.r(12); primary: true; text: Tr.t("Authenticate"); active: field.text !== ""; onClicked: root.submit() }
                }
            }
        }
    }

    Timer { id: focusTimer; interval: 30; onTriggered: field.input.forceActiveFocus() }
}
