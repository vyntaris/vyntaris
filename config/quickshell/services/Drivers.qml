pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property string tool: Quickshell.env("VYNTARIS_DRIVERS") || "/usr/lib/vyntaris/drivers"

    property var devices: []
    property bool surveying: false
    property bool installing: false
    property string failure: ""
    readonly property var missing: devices.filter(d => d.missing.length > 0)

    function survey() {
        if (surveying) return;
        surveying = true;
        scan.running = true;
    }
    Process {
        id: scan
        command: [root.tool]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.devices = JSON.parse(text).devices ?? []; } catch (e) { root.devices = []; }
            }
        }
        onExited: root.surveying = false
    }

    readonly property string nvidiaFile: "/etc/modprobe.d/vyntaris-nvidia-on-demand.conf"
    readonly property bool nvidiaAtStart: !/^blacklist nvidia/m.test(nvidiaStart.text())
    property bool nvidiaBusy: false
    FileView { id: nvidiaStart; path: root.nvidiaFile; printErrors: false; watchChanges: true; onFileChanged: reload() }
    function setNvidiaAtStart(on) {
        if (nvidiaBusy) return;
        nvidiaBusy = true;
        failure = "";
        nvidiaJob.command = ["pkexec", Quickshell.env("VYNTARIS_SETTINGS_ADMIN") || "/usr/lib/vyntaris/settings-admin",
            "nvidia-start", on ? "boot" : "demand"];
        nvidiaJob.running = true;
    }
    Process {
        id: nvidiaJob
        stderr: StdioCollector { id: nvidiaErr }
        onExited: code => {
            root.nvidiaBusy = false;
            if (code !== 0 && code !== 126 && code !== 127)
                root.failure = nvidiaErr.text.trim().split("\n").pop() || Tr.t("That couldn't be changed. Try again, or check that you're an administrator.");
            nvidiaStart.reload();
        }
    }

    function install() {
        if (installing) return;
        installing = true;
        failure = "";
        installer.running = true;
    }
    Process {
        id: installer
        command: ["pkexec", root.tool, "--install"]
        stderr: StdioCollector { id: installErr }
        onExited: code => {
            root.installing = false;
            if (code !== 0 && code !== 126 && code !== 127)
                root.failure = installErr.text.trim().split("\n").pop() || Tr.t("The drivers couldn't be installed. Check your connection and try again.");
            root.survey();
        }
    }

    FileView { id: uptime; path: "/proc/uptime"; blockLoading: true; printErrors: false }
    readonly property string seenFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/vyntaris/drivers-seen"
    FileView {
        id: seen
        path: root.seenFile
        printErrors: false
        blockLoading: true
    }
    FileView {
        path: "/var/lib/vyntaris/drivers.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let state = {};
            try { state = JSON.parse(text()); } catch (e) { return; }
            const all = state.installed ?? [];
            seen.reload();
            uptime.reload();
            const booted = Date.now() / 1000 - (parseFloat(uptime.text()) || 0);
            const last = Math.max(parseInt(seen.text()) || 0, booted);
            const fresh = all.filter(e => e.at > last);
            if (fresh.length === 0) return;
            for (const e of fresh) {
                Quickshell.execDetached(["notify-send", "-a", Tr.t("Drivers"), "-i", "preferences-system",
                    e.name + Tr.t(": driver installed"),
                    e.kind + (e.restart ? Tr.t(" · Restart to start using it.") : Tr.t(" · Ready to use."))]);
            }
            const newest = Math.max(...fresh.map(e => e.at));
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root.seenFile, String(newest)]);
            if (root.devices.length) root.survey();
        }
    }
}
