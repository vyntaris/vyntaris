import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import Quickshell.Services.UPower
import Quickshell.Io
import QtQuick
import qs.config
import qs.components

ShellRoot {
    id: root

    readonly property var cfg: Config.cfg
    // Everyone who can log in (a person's uid and a real shell), from /etc/passwd, which the greeter may read;
    // the one the settings came from first, and any other a click away.
    FileView { id: passwd; path: "/etc/passwd"; blockLoading: true; printErrors: false }
    readonly property var people: passwd.text().split("\n").map(l => l.split(":"))
        .filter(f => f.length >= 7 && +f[2] >= 1000 && +f[2] < 60000 && !/(nologin|false)$/.test(f[6]))
        .map(f => ({ name: f[0], full: (f[4] || "").split(",")[0] }))
    property string picked: ""
    readonly property string user: picked || cfg.user || (people[0]?.name ?? "")
    readonly property bool synced: user === cfg.user
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
                charging: UPower.displayDevice.state === UPowerDeviceState.Charging
                fullName: root.synced ? (root.cfg.fullName || "") : (root.people.find(p => p.name === root.user)?.full ?? "")
                face: root.synced ? (root.cfg.face || "") : ""
                others: root.people.filter(p => p.name !== root.user)
                onUserPicked: name => { if (root.status === "checking") return; root.picked = name; root.status = Greetd.available ? "" : root.status; }
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
