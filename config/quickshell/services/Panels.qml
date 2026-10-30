pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    property bool launcherOpen: false
    property string launcherQuery: ""
    property bool systemOpen: false
    property bool batteryOpen: false
    property bool wallpaperOpen: false
    property bool controlOpen: false
    property bool mediaOpen: false
    property bool updatesOpen: false
    property bool packagesOpen: false
    property bool cloudOpen: false
    property bool nightOpen: false
    property bool gameOpen: false
    property bool soundOpen: false
    property bool overviewOpen: false
    property bool awakeOpen: false
    property bool appsOpen: false
    property bool wifiOpen: false
    property bool wifiTyping: false
    property bool vpnOpen: false
    property bool keyboardOpen: false
    property bool bluetoothOpen: false
    property bool phoneOpen: false
    property bool captureOpen: false
    property bool powerOpen: false
    property bool privacyOpen: false
    property bool gpuOpen: false
    property string timerTab: ""
    property bool timerOpen: false
    property bool settingsOpen: false
    property bool welcomeOpen: false
    property bool helpOpen: false
    property bool backupOpen: false
    property bool healthOpen: false
    property bool storeOpen: false

    readonly property var islandPanels: [
        "launcher", "system", "battery", "wallpaper", "control", "media", "updates", "packages", "cloud", "night", "game", "sound", "overview",
        "awake", "apps", "wifi", "vpn", "keyboard", "bluetooth", "phone", "capture", "power", "privacy", "gpu", "timer",
    ]

    function only(name) {
        for (const p of islandPanels)
            if (p !== name && root[p + "Open"]) root[p + "Open"] = false;
    }
    function closeAll() { only(""); }

    onLauncherOpenChanged: if (launcherOpen) only("launcher")
    onSystemOpenChanged: if (systemOpen) only("system")
    onBatteryOpenChanged: if (batteryOpen) only("battery")
    onWallpaperOpenChanged: if (wallpaperOpen) only("wallpaper")
    onControlOpenChanged: if (controlOpen) only("control")
    onMediaOpenChanged: if (mediaOpen) only("media")
    onUpdatesOpenChanged: if (updatesOpen) only("updates")
    onPackagesOpenChanged: if (packagesOpen) only("packages")
    onCloudOpenChanged: if (cloudOpen) only("cloud")
    onNightOpenChanged: if (nightOpen) only("night")
    onGameOpenChanged: if (gameOpen) only("game")
    onSoundOpenChanged: if (soundOpen) only("sound")
    onOverviewOpenChanged: if (overviewOpen) only("overview"); else overviewByAlt = false
    onAwakeOpenChanged: if (awakeOpen) only("awake")
    onAppsOpenChanged: if (appsOpen) only("apps")
    onWifiOpenChanged: if (wifiOpen) only("wifi")
    onVpnOpenChanged: if (vpnOpen) only("vpn")
    onKeyboardOpenChanged: if (keyboardOpen) only("keyboard")
    onBluetoothOpenChanged: if (bluetoothOpen) only("bluetooth")
    onPhoneOpenChanged: if (phoneOpen) only("phone")
    onCaptureOpenChanged: if (captureOpen) only("capture")
    onPowerOpenChanged: if (powerOpen) only("power")
    onTimerOpenChanged: if (timerOpen) only("timer")
    onPrivacyOpenChanged: if (privacyOpen) only("privacy")
    onGpuOpenChanged: if (gpuOpen) only("gpu")

    property string app: ""
    readonly property var appFlags: ({ settings: "settings", store: "store", help: "help", doctor: "health", backup: "backup" })
    function openApp(name, call, arg) {
        if (app === name) { root[appFlags[name] + "Open"] = true; return; }
        Quickshell.execDetached([Quickshell.shellPath("scripts/app.sh"), name, call || "open", arg ?? ""]);
    }
    function closeApp(name) {
        if (app === name) { root[appFlags[name] + "Open"] = false; return; }
        Quickshell.execDetached([Quickshell.shellPath("scripts/app.sh"), name, "close"]);
    }
    function inShell(target, fn) {
        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call", target, fn]);
    }
    onSettingsOpenChanged: handOver("settings")
    onStoreOpenChanged: handOver("store")
    onHelpOpenChanged: handOver("help")
    onBackupOpenChanged: handOver("backup")
    onHealthOpenChanged: handOver("doctor")
    function handOver(name) {
        const flag = appFlags[name] + "Open";
        if (app === name || !root[flag]) return;
        root[flag] = false;
        openApp(name);
    }

    function store(text) { openApp("store", "search", text ?? ""); }
    property string settingsPage: "appearance"
    signal settingsSearchRequested(string text)
    function settingsSearch(text) {
        if (app !== "settings") { openApp("settings", "search", text); return; }
        settingsOpen = true;
        settingsSearchRequested(text);
    }
    readonly property var islandPages: ({ night: ["nightlight", "nightOpen"], game: ["gamemode", "gameOpen"] })
    function islandPage(page) {
        const p = islandPages[page];
        if (!p) return false;
        if (app) inShell(p[0], "panel");
        else root[p[1]] = true;
        return true;
    }
    function settings(page) {
        if (islandPage(page)) return;
        if (page === "welcome") { if (app) inShell("welcome", "open"); else welcomeOpen = true; return; }
        if (page === "help") { openApp("help"); return; }
        if (app !== "settings") { openApp("settings", "page", page ?? ""); return; }
        settingsOpen = true;
        if (page) settingsPage = page;
    }
    property string settingsFocus: ""
    function settingsRow(page, title) {
        if (islandPage(page)) return;
        if (app !== "settings") { openApp("settings", "row", page + "\t" + (title ?? "")); return; }
        settings(page);
        settingsFocus = title ?? "";
    }

    function search(text) {
        launcherQuery = text;
        launcherOpen = true;
    }

    function keyboard() {
        if (keyboardOpen) Keyboard.next();
        else keyboardOpen = true;
    }

    signal overviewStep(int delta)
    function overview(delta) {
        if (overviewOpen) overviewStep(delta);
        else { overviewByAlt = true; overviewOpen = true; }
    }
    property bool overviewByAlt: false
    signal overviewCommitted()
    property bool overviewCommitPending: false
    function overviewCommit() {
        if (overviewOpen) { if (overviewByAlt) overviewCommitted(); }
        else { overviewCommitPending = true; commitExpiry.restart(); }
    }
    property Timer commitExpiry: Timer { interval: 500; onTriggered: root.overviewCommitPending = false }

    readonly property bool anyIslandPanel: islandPanels.some(p => root[p + "Open"])
    readonly property bool needsKeyboard: wifiTyping || launcherOpen || appsOpen || powerOpen || wallpaperOpen || overviewOpen || keyboardOpen || captureOpen || timerOpen || nightOpen
}
