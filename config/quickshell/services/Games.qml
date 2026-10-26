pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property string lib: Quickshell.env("VYNTARIS_LIB") || "/usr/lib/vyntaris"
    readonly property string logDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/vyntaris-mangohud"

    property int fps: -1
    property int cpuTemp: -1
    property int gpuTemp: -1
    property int gpuLoad: -1
    readonly property bool known: fps >= 0 || cpuTemp >= 0 || gpuTemp >= 0

    readonly property bool watching: GameMode.active && Config.gameMode.stats
    onWatchingChanged: if (!watching) { fps = -1; cpuTemp = -1; gpuTemp = -1; gpuLoad = -1; }
    Timer {
        interval: 1500
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!stats.running) stats.running = true
    }
    Process {
        id: stats
        command: [root.lib + "/game-stats", root.logDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(s => s === "-" ? -1 : parseInt(s));
                if (v.length !== 4 || v.some(n => isNaN(n))) return;
                [root.fps, root.cpuTemp, root.gpuTemp, root.gpuLoad] = v;
            }
        }
    }

    property bool multilib: false
    property var installed: []
    readonly property bool ready: installed.includes("steam")
    function refresh() { status.running = true; }
    Process {
        id: status
        command: [root.lib + "/gaming", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.multilib = s.multilib === true;
                    root.installed = s.installed ?? [];
                } catch (e) {}
            }
        }
    }
    function setUp() {
        Config.runInTerminal('sudo ' + root.lib + '/gaming --setup; ' + Config.enterToClose());
    }

    readonly property var launchers: ["steam", "net.lutris.Lutris", "lutris", "com.heroicgameslauncher.hgl", "heroic"]
    function isLauncher(entry) {
        return launchers.includes((entry?.id ?? "").replace(/\.desktop$/, ""));
    }
    function launch(entry) {
        if (!isLauncher(entry) || !installed.includes("mangohud") || !(entry.command?.length > 0)) return false;
        Config.launch(["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", logDir,
            "env", "MANGOHUD=1",
            "MANGOHUD_CONFIG=no_display,output_folder=" + logDir + ",log_interval=1000,autostart_log=1"]
            .concat(entry.command));
        return true;
    }
    Component.onCompleted: refresh()
}
