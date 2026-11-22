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

    // It comes and goes as the lock screen does: the desktop behind blurs and pushes in, the padlock shuts. On the
    // right password the padlock turns green and opens, the card drops away and the desktop sharpens back to exactly
    // what's behind, then the window goes. `shown` keeps it up while it leaves.
    property bool shown: false
    property bool succeeded: false
    property real glass: 0
    property real leave: 0
    NumberAnimation { id: glassIn; target: root; property: "glass"; to: 1; duration: Theme.duration(450); easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: away
        ParallelAnimation {
            NumberAnimation { target: root; property: "leave"; to: 1; duration: Theme.duration(420); easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "glass"; to: 0; duration: Theme.duration(520); easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: { root.shown = false; root.succeeded = false; } }
    }
    // polkit lets go of the request at once: what the card says is kept for the way out.
    property string lastMessage: ""
    property string lastName: ""
    Binding { target: root; property: "lastMessage"; value: root.flow?.message ?? ""; when: root.flow !== null }
    Binding { target: root; property: "lastName"; value: root.flow?.selectedIdentity?.displayName || Quickshell.env("USER") || ""; when: root.flow !== null }

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
        function onAuthenticationSucceeded() { root.succeeded = true; }
        // Ready for another: typing went on during a quiet check, so check what's there now.
        function onIsResponseRequiredChanged() { if (root.flow?.isResponseRequired) { focusTimer.restart(); if (root.quiet) pause.restart(); } }
    }
    onOpenChanged: {
        showPassword = false;
        quiet = false;
        checked = "";
        if (open) {
            away.stop();
            glassIn.stop();
            leave = 0;
            glass = 0;
            succeeded = false;
            shown = true;
            focusTimer.restart();
        } else {
            field.text = "";
            if (shown) { glassIn.stop(); away.restart(); }
        }
    }

    PanelWindow {
        id: win
        visible: root.shown
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
            captureSource: root.shown ? win.screen : null
            live: false
            visible: false
            onHasContentChanged: if (hasContent && root.open) glassIn.restart()
        }
        // The desktop as it was: sharp and in place at 0, so the window can go without a jump.
        Item {
            anchors.fill: parent
            visible: shot.hasContent
            MultiEffect {
                anchors.fill: parent
                source: shot
                autoPaddingEnabled: false
                scale: 1 + 0.05 * root.glass
                blurEnabled: true
                blur: root.glass
                blurMax: 64
                blurMultiplier: 0.6
            }
            Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.base, 0.32); opacity: root.glass }
        }
        MouseArea { anchors.fill: parent }

        Rectangle {
            id: card
            visible: shot.hasContent
            anchors.centerIn: parent
            width: 420
            height: body.implicitHeight + 48
            radius: Theme.r(20)
            border { width: 1; color: root.succeeded ? Theme.tint(parent, Theme.success, 0.7) : root.flow?.failed && !root.quiet ? Theme.tint(parent, Theme.error, 0.6) : Theme.edgeOn(parent) }
            color: Theme.isDark ? Theme.crust : Theme.base
            transform: [ Translate { id: shakeShift }, Translate { y: 50 * root.leave } ]
            // Comes up with the blur, drops away as it leaves.
            opacity: Math.min(1, root.glass * 1.6) * (1 - root.leave)
            scale: (0.94 + 0.06 * Math.min(1, root.glass * 1.4)) * (1 - 0.06 * root.leave)

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
                        color: root.succeeded ? Theme.success : Theme.accent
                        Behavior on color { ColorAnim {} }
                        Padlock {
                            anchors.centerIn: parent
                            size: 20
                            color: Theme.textOnAccent
                            open: root.succeeded ? 1 - root.glass : Math.max(0, 1 - root.glass * 1.25)
                        }
                    }
                    ColumnLayout {
                        spacing: Theme.space2
                        Label { overline: true; color: Theme.accentInk; text: Tr.t("Authentication required") }
                        // Whose password polkit asks for: the chosen identity, not necessarily who is signed in.
                        Label {
                            color: Theme.subtext0
                            font.pixelSize: Theme.fontSizeSmall
                            text: root.lastName
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.lastMessage
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
