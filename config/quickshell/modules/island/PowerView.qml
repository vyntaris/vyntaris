import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real hang: actionRow.implicitHeight + 20
    readonly property bool active: Panels.powerOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var allActions: [
        { id: "lock",      label: Tr.t("Lock"),      icon: "lock",    command: Config.power.lock,      confirm: false },
        { id: "logout",    label: Tr.t("Log out"),   icon: "logout",  command: Config.power.logout,    confirm: true },
        { id: "suspend",   label: Tr.t("Suspend"),   icon: "moon",    command: Config.power.suspend,   confirm: false },
        { id: "hibernate", label: Tr.t("Hibernate"), icon: "disk",    command: Config.power.hibernate, confirm: true },
        { id: "reboot",    label: Tr.t("Restart"),   icon: "restart", command: Config.power.reboot,    confirm: true },
        { id: "shutdown",  label: Tr.t("Shut down"), icon: "power",   command: Config.power.shutdown,  confirm: true },
    ]

    readonly property var actions: allActions.filter(a => a.id !== "hibernate" || Sleep.canHibernate)
    readonly property real fullWidth: Math.max(480, actions.length * 84 + 40)

    // Never starts on what ends the session: Enter alone only ever locks.
    property int current: 0
    property string pending: ""

    function enabled(a) { return a.id !== "hibernate" || Sleep.canHibernate; }

    function activate(i) {
        const a = actions[i];
        if (!a || !enabled(a)) return;
        if (a.confirm && pending !== a.id) {
            pending = a.id;
            current = i;
            confirmTimer.restart();
            return;
        }
        pending = "";
        Panels.powerOpen = false;
        if (a.id === "shutdown" || a.id === "reboot" || a.id === "logout") Leaving.run(a.id, a.command);
        else Config.launch(["sh", "-c", a.command]);
    }

    Timer { id: confirmTimer; interval: 3000; onTriggered: root.pending = "" }

    Component.onCompleted: if (active) activeChanged()
    onActiveChanged: {
        pending = "";
        if (active) { current = 0; uptimeFile.reload(); focusTimer.restart(); }
    }
    Timer { id: focusTimer; interval: 30; onTriggered: keys.forceActiveFocus() }
    Connections {
        target: root.Window.window
        function onActiveChanged() { if (root.active && root.Window.window.active) keys.forceActiveFocus(); }
    }

    FileView { id: uptimeFile; path: "/proc/uptime" }
    readonly property string uptime: {
        const s = Math.floor(parseFloat(uptimeFile.text()) || 0);
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return (d > 0 ? d + "d " : "") + h + "h " + String(m).padStart(2, "0") + "m";
    }

    Item {
        id: keys
        anchors.fill: parent
        readonly property int count: root.actions.length
        Keys.onEscapePressed: Panels.powerOpen = false
        Keys.onLeftPressed: { root.current = (root.current + count - 1) % count; root.pending = ""; }
        Keys.onRightPressed: { root.current = (root.current + 1) % count; root.pending = ""; }
        Keys.onTabPressed: { root.current = (root.current + 1) % count; root.pending = ""; }
        Keys.onReturnPressed: root.activate(root.current)
        Keys.onEnterPressed: root.activate(root.current)
        Keys.onPressed: event => {
            const n = parseInt(event.text);
            if (n >= 1 && n <= count) { root.current = n - 1; root.activate(n - 1); event.accepted = true; }
        }
    }

    PanelHeader {
        icon: "power"
        title: root.pending ? Tr.t("Press again to confirm") : Tr.f("Goodbye, {0}", Quickshell.env("USER"))
        tint: root.pending ? Theme.error : Theme.accent
        Label { overline: true; color: Theme.overlay1; text: Tr.t("Uptime") }
        Label { mono: true; font.pixelSize: Theme.fontSizeLabel; text: root.uptime }
    }

    Row {
        id: actionRow
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.barHeight + 8
        spacing: Theme.space12

        Repeater {
            model: root.actions

            RoundToggle {
                id: btn
                required property var modelData
                required property int index
                readonly property bool usable: root.enabled(modelData)
                readonly property bool selected: root.current === index
                readonly property bool arming: root.pending === modelData.id

                icon: modelData.icon
                label: arming ? Tr.f("{0}?", modelData.label) : modelData.label
                tint: arming ? Theme.error : Theme.accent
                on: arming || selected
                enabled: usable
                opacity: usable ? 1 : Theme.disabledOpacity
                onEntered: { if (root.current !== btn.index) root.pending = ""; root.current = btn.index; }
                onClicked: root.activate(btn.index)

                scale: root.active ? 1 : 0.6
                Behavior on scale {
                    SequentialAnimation {
                        PauseAnimation { duration: root.active ? Theme.duration(60 + btn.index * 40) : 0 }
                        Anim { duration: Theme.durationSlow; easing.bezierCurve: Theme.curveSpring }
                    }
                }
            }
        }
    }

}
