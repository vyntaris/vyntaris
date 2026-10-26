import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.config
import qs.services

ShellRoot {
    id: root
    required property string name
    required property string flag
    property string windowTitle
    property int keepFor: 120000
    signal called(string call, string arg)

    readonly property bool open: Panels[flag + "Open"]

    function handle(call, arg) {
        if (call === "toggle" && open && focused()) { Panels[flag + "Open"] = false; return; }
        if (open && windowTitle)
            Compositor.dispatch(`hl.dsp.focus({ window = "title:^${windowTitle.replace(/\./g, "\\\\.")}$" })`);
        called(call === "toggle" ? "open" : call, arg);
        Panels[flag + "Open"] = true;
    }
    function focused() { return Hyprland.activeToplevel?.title === windowTitle; }

    IpcHandler {
        target: "app"
        function open(call: string, arg: string): void { root.handle(call || "open", arg) }
        function close(): void { Panels[root.flag + "Open"] = false }
    }

    Component.onCompleted: {
        Quickshell.watchFiles = !Quickshell.shellDir.startsWith("/etc/xdg/");
        void Hyprland.activeToplevel;
        Panels.app = name;
        Config.leader = false;
        handle(Quickshell.env("VYNTARIS_APP_CALL") || "open", Quickshell.env("VYNTARIS_APP_ARG") || "");
    }
    onOpenChanged: open ? end.stop() : end.restart()
    Timer {
        id: end
        interval: root.keepFor
        onTriggered: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(root.name + ".qml"), "kill"])
    }
}
