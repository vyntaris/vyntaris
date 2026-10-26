pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    property bool airplane: false
    property bool hasRadios: false
    property bool radiosKnown: false

    readonly property string flagFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/vyntaris/airplane"
    property bool chosen: false
    function setAirplane(on) {
        remember(on);
        Quickshell.execDetached(["rfkill", on ? "block" : "unblock", "all"]);
    }
    property real chosenAt: 0
    function remember(on) {
        chosen = on;
        if (on) chosenAt = Date.now();
        Quickshell.execDetached(["sh", "-c", on ? 'mkdir -p "$(dirname "$1")" && : > "$1"' : 'rm -f "$1"', "sh", root.flagFile]);
    }
    Process {
        running: true
        command: ["test", "-e", root.flagFile]
        onExited: code => { root.chosen = code === 0; rfkillList.running = true; }
    }
    function toggleAirplane() { setAirplane(!airplane); }
    function airplaneKey() {
        keyState = airplane;
        keyWait.restart();
    }
    property bool keyState: false
    Timer {
        id: keyWait
        interval: 450
        onTriggered: if (root.airplane === root.keyState) root.toggleAirplane(); else Osd.show("airplane")
    }

    Process {
        id: rfkillList
        command: ["rfkill", "-J"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devs = JSON.parse(text).rfkilldevices ?? [];
                    const was = root.airplane;
                    root.hasRadios = devs.length > 0;
                    const allOff = root.hasRadios && devs.every(d => d.soft === "blocked" || d.hard === "blocked");
                    const switched = root.hasRadios && devs.some(d => d.type === "wlan" && d.hard === "blocked");
                    if (root.chosen && !allOff && Date.now() - root.chosenAt > 2000) root.remember(false);
                    root.airplane = switched || (root.chosen && allOff);
                    if (root.radiosKnown && was !== root.airplane && !keyWait.running) Osd.show("airplane");
                    root.radiosKnown = true;
                } catch (e) {}
            }
        }
    }
    Process {
        running: true
        command: ["rfkill", "event"]
        stdout: SplitParser { onRead: rfkillDebounce.restart() }
    }
    Timer { id: rfkillDebounce; interval: 150; onTriggered: rfkillList.running = true }

    property string touchpadName: ""
    property bool touchpad: true

    function setTouchpad(on) {
        if (!touchpadName) return;
        touchpad = on;
        Quickshell.execDetached(["hyprctl", "eval", `hl.device({ name = "${touchpadName}", enabled = ${on} })`]);
        Osd.show("touchpad");
    }
    function toggleTouchpad() { setTouchpad(!touchpad); }

    Process {
        id: devices
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const pad = (JSON.parse(text).mice ?? []).find(m => /touchpad/i.test(m.name));
                    root.touchpadName = pad?.name ?? "";
                } catch (e) {}
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && !root.touchpad && root.touchpadName)
                Quickshell.execDetached(["hyprctl", "eval", `hl.device({ name = "${root.touchpadName}", enabled = false })`]);
        }
    }

    readonly property string cameraFile: "/sys/bus/platform/devices/VPC2004:00/camera_power"
    property bool hasCameraSwitch: false
    property bool camera: false
    property bool cameraKnown: false
    property bool cameraHint: false

    FileView {
        id: cameraSeen
        path: Quickshell.statePath("camera-seen")
        printErrors: false
        onLoaded: root.hasCameraSwitch = true
    }
    component SwitchFile: FileView {
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    property bool hasPrivacySwitch: false
    SwitchFile {
        id: privacySwitch
        path: "/run/laptop-switches/camera"
        onLoaded: {
            const on = text().trim() === "on";
            const first = !root.hasPrivacySwitch;
            root.hasPrivacySwitch = true;
            root.hasCameraSwitch = true;
            root.cameraHint = false;
            if (!first && on !== root.camera) { root.camera = on; Osd.show("camera"); }
            root.camera = on;
            root.cameraKnown = true;
        }
        onLoadFailed: root.hasPrivacySwitch = false
    }

    Process {
        id: cameraCheck
        command: ["sh", "-c", "ls /dev/video* >/dev/null 2>&1"]
        onExited: code => {
            if (root.hasPrivacySwitch) return;
            const on = code === 0;
            if (on && !root.hasCameraSwitch) { root.hasCameraSwitch = true; cameraSeen.setText("1"); }
            if (root.cameraKnown && on !== root.camera) { root.camera = on; root.cameraHint = false; Osd.show("camera"); }
            root.camera = on;
            root.cameraKnown = true;
        }
    }
    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=video4linux"]
        stdout: SplitParser { onRead: cameraDebounce.restart() }
    }
    Timer { id: cameraDebounce; interval: 300; onTriggered: cameraCheck.running = true }

    function setCamera(on) {
        Quickshell.execDetached(["sh", "-c", '[ -w "$1" ] && printf %s "$2" > "$1"', "sh", cameraFile, on ? "1" : "0"]);
        cameraResult.wanted = on;
        cameraResult.restart();
    }
    function cameraKey() {
        if (hasPrivacySwitch) { cameraHint = true; Osd.show("camera"); return; }
        setCamera(!camera);
    }
    Timer {
        id: cameraResult
        property bool wanted
        interval: 1500
        onTriggered: if (root.camera !== wanted) { root.cameraHint = true; Osd.show("camera"); }
    }

    property bool hasFnLock: false
    property bool fnLock: false
    property bool fnKnown: false
    SwitchFile {
        id: fnFile
        path: "/run/laptop-switches/fnlock"
        onLoaded: {
            const on = text().trim() === "on";
            root.hasFnLock = true;
            if (root.fnKnown && on !== root.fnLock) { root.fnLock = on; Osd.show("fnlock"); }
            root.fnLock = on;
            root.fnKnown = true;
        }
        onLoadFailed: { root.hasFnLock = false; root.fnKnown = true; }
    }

    property bool vrr: false
    function toggleVrr() {
        vrr = !vrr;
        Quickshell.execDetached(["hyprctl", "eval", `hl.config({ misc = { vrr = ${vrr ? 1 : 0} } })`]);
        Osd.show("vrr");
    }
    Process {
        running: true
        command: ["hyprctl", "-j", "getoption", "misc.vrr"]
        stdout: StdioCollector { onStreamFinished: { try { root.vrr = (JSON.parse(text).int ?? 0) > 0; } catch (e) {} } }
    }

    Component.onCompleted: { rfkillList.running = true; cameraCheck.running = true; }
}
