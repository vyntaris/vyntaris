import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import Quickshell.Services.UPower
import QtQuick
import qs.config
import qs.components

ShellRoot {
    id: root

    readonly property var cfg: Config.cfg
    readonly property string user: cfg.user || Quickshell.env("USER") || ""
    readonly property var session: cfg.session ?? ["vyntaris-session"]
    property string status: Greetd.available ? "" : "Preview — not under greetd (Esc quits)"
    property string pending: ""

    function login(pw) {
        if (!Greetd.available) { status = "wrong"; return; }
        if (status === "checking" || !user) return;
        pending = pw;
        status = "checking";
        Greetd.createSession(user);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) { Greetd.respond(root.pending); root.pending = ""; }
            else if (error) root.status = message;
        }
        function onAuthFailure(message) {
            root.status = "wrong";
            Greetd.cancelSession();
        }
        function onReadyToLaunch() {
            root.status = "Starting…";
            Greetd.launch(root.session);
        }
        function onError(error) { root.status = String(error); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            readonly property bool primary: modelData === Quickshell.screens[0]
            screen: modelData
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Theme.crust

            LockFace {
                anchors.fill: parent
                visible: win.primary
                active: win.primary
                user: root.user
                battery: UPower.displayDevice.isLaptopBattery ? Math.round(UPower.displayDevice.percentage * 100) : -1
                charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
                fullName: root.cfg.fullName || ""
                face: root.cfg.face || ""
                status: root.status
                wallpaper: root.cfg.wallpaper || ""
                title: "Welcome"
                showPower: true
                onSubmit: pw => root.login(pw)
                onPowerClicked: action => Quickshell.execDetached(["systemctl", action])
                Keys.onEscapePressed: if (!Greetd.available) Qt.quit()
            }
        }
    }
}
