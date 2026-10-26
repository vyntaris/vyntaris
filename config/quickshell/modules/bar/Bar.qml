import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import "../../components/Slant.js" as Slant
import "../../components/Icons.js" as Icons
import qs.services
import qs.modules.island
import qs.modules.edges

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    readonly property bool primary: Monitors.focused?.name === modelData.name

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: mode !== "clock" || Compositor.fullscreenMode === 1 || Compositor.fullscreenMode === 3
        ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.Exclusive
        : primary && Screenshot.shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true }
    implicitHeight: modelData.height
    exclusiveZone: Theme.barHeight + Theme.notchDepth
    color: "transparent"

    readonly property bool popupOpen: primary && Panels.anyIslandPanel

    function closePopups() {
        Panels.closeAll();
    }

    Item {
        id: escCatcher
        Keys.onEscapePressed: bar.closePopups()
        Keys.onReleased: event => { if (event.key === Qt.Key_Alt && Panels.overviewOpen) Panels.overviewCommit(); }
        Keys.onPressed: event => {
            const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
            const typed = plain && event.text.length === 1 && event.text.trim() !== "" && event.text.charCodeAt(0) >= 32;
            if (!typed) return;
            if (Panels.launcherOpen && launcherView.item) {
                launcherView.item.typeIn(event.text);
                event.accepted = true;
            } else if (Panels.controlOpen) {
                Panels.search(event.text);
                event.accepted = true;
            }
        }
    }
    onPopupOpenChanged: if (popupOpen) {
        if (!escCatcher.Window.activeFocusItem) escCatcher.forceActiveFocus();
        escFocus.restart();
    }
    Timer {
        id: escFocus
        interval: 40
        onTriggered: if (!Panels.needsKeyboard) escCatcher.forceActiveFocus()
    }
    Connections {
        target: Panels
        function onNeedsKeyboardChanged() { if (bar.popupOpen && !Panels.needsKeyboard) escFocus.restart(); }
    }
    Connections {
        target: escCatcher.Window.window
        function onActiveChanged() {
            if (bar.popupOpen && !Panels.needsKeyboard && escCatcher.Window.window.active) escCatcher.forceActiveFocus();
        }
    }

    property int maskRev: 0
    Timer {
        id: maskKick
        property int left: 4
        interval: 700
        running: true
        repeat: true
        onTriggered: { bar.maskRev++; if (--left <= 0) { stop(); left = 4; } }
    }
    onWidthChanged: maskKick.restart()
    onHeightChanged: maskKick.restart()
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (/^(monitoradded|monitorremoved|configreloaded)/.test(event.name)) maskKick.restart();
        }
    }

    mask: Region {
        item: bar.popupOpen ? catcher : strip
        Region { item: islandArea }
        Region { item: edges.volumeZone }
        Region { item: edges.brightnessZone }
        Region { item: edges.cornerZone }
    }

    Component.onCompleted: {
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
    }

    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifiDevice?.networks.values.find(n => n.connected) ?? null
    readonly property bool wired: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property var audio: Pipewire.defaultAudioSink?.audio ?? null
    readonly property var mic: Pipewire.defaultAudioSource?.audio ?? null
    PwObjectTracker { objects: [ Pipewire.defaultAudioSink, Pipewire.defaultAudioSource ] }

    IdleInhibitor {
        window: bar
        enabled: KeepAwake.inhibitDisplay && bar.primary
    }

    readonly property string mode: !primary ? "clock"
        : Recorder.counting ? "countdown"
        : Panels.launcherOpen ? "launcher"
        : Panels.overviewOpen ? "overview"
        : Panels.powerOpen ? "power"
        : Panels.timerOpen ? "timer"
        : Panels.privacyOpen ? "privacy"
        : Panels.gpuOpen ? "gpu"
        : Panels.wallpaperOpen ? "wallpaper"
        : Panels.controlOpen ? "control"
        : Panels.awakeOpen ? "awake"
        : Panels.appsOpen ? "apps"
        : Panels.wifiOpen ? "wifi"
        : Panels.vpnOpen ? "vpn"
        : Panels.keyboardOpen ? "keyboard"
        : Panels.bluetoothOpen ? "bluetooth"
        : Panels.phoneOpen ? "phone"
        : Panels.captureOpen ? "capture"
        : Panels.mediaOpen ? "media"
        : Panels.updatesOpen ? "updates"
        : Panels.packagesOpen ? "packages"
        : Panels.cloudOpen ? "cloud"
        : Panels.nightOpen ? "night"
        : Panels.gameOpen ? "gamepanel"
        : Panels.soundOpen ? "sound"
        : Panels.systemOpen ? "system"
        : Panels.batteryOpen ? "battery"
        : Screenshot.shown ? "screenshot"
        : Activities.shown ? "activity"
        : Osd.shown ? "osd"
        : Notifications.current ? "notification"
        : Games.watching && Games.known && Compositor.fullscreenMode !== 2 ? "game"
        : "clock"
    readonly property var views: ({
        clock: clockView.item, launcher: launcherView.item, overview: overviewView.item, power: powerView.item,
        wallpaper: wallpaperView.item, control: controlView.item, media: mediaView.item,
        updates: updatesView.item, packages: packagesView.item, cloud: cloudView.item, night: nightView.item, gamepanel: gameModeView.item, sound: soundView.item, awake: awakeView.item, apps: appsView.item, wifi: wifiPanel.item, vpn: vpnPanel.item, keyboard: keyboardView.item, bluetooth: bluetoothView.item, phone: phoneView.item, capture: captureView.item, system: systemView.item, battery: batteryView.item, screenshot: screenshotView.item,
        osd: osdView.item, notification: notificationView.item, privacy: privacyView.item, gpu: gpuView.item, timer: timerView.item,
        activity: activityView.item, countdown: countdownView.item, game: gameView.item,
    })
    readonly property Item activeView: views[mode] ?? clockView.item

    property real islandWidth: activeView.fullWidth
    property real islandHang: activeView.hang
    property bool widthGrows: true
    property bool hangGrows: true
    readonly property real targetWidth: activeView.fullWidth
    readonly property real targetHang: activeView.hang
    onTargetWidthChanged: { widthGrows = targetWidth > islandWidth; islandWidth = targetWidth; }
    onTargetHangChanged: {
        hangGrows = targetHang > islandHang;
        islandHang = targetHang;
    }
    Behavior on islandWidth { Anim { duration: Theme.durationSlow; easing.bezierCurve: bar.widthGrows ? Theme.curveIsland : Theme.curveStandard } }
    Behavior on islandHang { Anim { duration: Theme.durationSlow; easing.bezierCurve: bar.hangGrows ? Theme.curveIsland : Theme.curveStandard } }

    component Divider: Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 12
        color: Theme.hairline
    }

    component Module: Item {
        id: mod
        default property alias items: row.data
        property bool active: false
        signal clicked(var mouse)
        signal scrolled(int direction)

        implicitWidth: row.implicitWidth + 18
        implicitHeight: Theme.barHeight - 8

        Rectangle {
            anchors.fill: parent
            radius: Theme.r(height / 2)
            color: mod.active ? Theme.alpha(Theme.accent, 0.16)
                 : area.containsMouse ? Theme.hover : "transparent"
            Behavior on color { ColorAnim {} }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 7
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => mod.clicked(mouse)
            onWheel: wheel => mod.scrolled(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }

    Item {
        id: content
        readonly property bool solidIcons: true
        width: parent.width
        height: parent.height

        y: shown ? 0 : -Theme.barHeight - Theme.notchDepth - 4
        property bool shown: false
        Component.onCompleted: shown = true
        Behavior on y { Anim { duration: Theme.durationSlow; easing.bezierCurve: Theme.curveDecelerate } }

        BarShape {
            anchors.fill: parent
            drawers: [
                { center: bar.width / 2, width: bar.islandWidth, hang: bar.islandHang },
            ]
        }

        MouseArea {
            id: catcher
            anchors.fill: parent
            enabled: bar.popupOpen
            acceptedButtons: Qt.AllButtons
            onPressed: bar.closePopups()
        }

        Item { id: strip; width: parent.width - (bar.maskRev % 2); height: Theme.barHeight }
        readonly property real islandLean: Theme.slanted ? Slant.lean(bar.islandHang) : 0
        MouseArea {
            id: islandArea
            x: (bar.width - bar.islandWidth) / 2 - parent.islandLean
            width: bar.islandWidth + 2 * parent.islandLean
            height: Theme.barHeight + bar.islandHang
        }

        Item {
            id: islandClip
            z: 2
            x: (bar.width - bar.islandWidth) / 2 - parent.islandLean
            width: bar.islandWidth + 2 * parent.islandLean
            height: Theme.barHeight + bar.islandHang
            clip: true

            component View: Item {
                id: view
                property string name
                property bool stays: false
                property bool kept: false
                default property Component content
                readonly property bool current: bar.mode === name
                readonly property Item item: loader.item
                x: (islandClip.width - width) / 2
                width: item?.width ?? 0
                height: item?.height ?? 0
                opacity: current ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    Anim { duration: view.current ? Theme.durationNormal : Theme.durationFast }
                }

                property bool held: false
                onCurrentChanged: {
                    if (current) { held = true; release.stop(); }
                    else release.restart();
                }
                Timer { id: release; interval: view.kept ? 600000 : 120000; onTriggered: view.held = view.current }
                Loader { id: loader; active: view.stays || view.held || view.current; sourceComponent: view.content }
            }

            View { id: clockView; name: "clock"; stays: true; ClockView {} }
            View { id: osdView; name: "osd"; stays: true; OsdView {} }
            View { id: notificationView; name: "notification"; stays: true; NotificationView {} }
            View { id: launcherView; name: "launcher"; stays: true; LauncherView {} }
            View { id: systemView; name: "system"; SystemView {} }
            View { id: batteryView; name: "battery"; BatteryView {} }
            View { id: wallpaperView; name: "wallpaper"; WallpaperView {} }
            View { id: controlView; name: "control"; stays: true; ControlView {} }
            View { id: mediaView; name: "media"; MediaView {} }
            View { id: updatesView; name: "updates"; UpdatesView {} }
            View { id: packagesView; name: "packages"; PackagesView {} }
            View { id: cloudView; name: "cloud"; CloudView {} }
            View { id: nightView; name: "night"; NightView {} }
            View { id: gameModeView; name: "gamepanel"; GameModeView {} }
            View { id: soundView; name: "sound"; SoundView {} }
            View { id: overviewView; name: "overview"; OverviewView {} }
            View { id: screenshotView; name: "screenshot"; ScreenshotView {} }
            View { id: awakeView; name: "awake"; AwakeView {} }
            View { id: appsView; name: "apps"; kept: true; AppsView {} }
            View { id: powerView; name: "power"; PowerView {} }
            View { id: keyboardView; name: "keyboard"; KeyboardView {} }
            View { id: bluetoothView; name: "bluetooth"; BluetoothView {} }
            View { id: phoneView; name: "phone"; PhoneView {} }
            View { id: captureView; name: "capture"; CaptureView {} }
            View { id: privacyView; name: "privacy"; PrivacyView {} }
            View { id: gpuView; name: "gpu"; GpuView {} }
            View { id: timerView; name: "timer"; TimerView {} }
            View { id: activityView; name: "activity"; ActivityView {} }
            View { id: countdownView; name: "countdown"; CountdownView {} }
            View { id: wifiPanel; name: "wifi"; WifiPanel {} }
            View { id: vpnPanel; name: "vpn"; VpnPanel {} }
            View { id: gameView; name: "game"; GameView {} }
        }

        RowLayout {
            anchors { left: parent.left; leftMargin: 8 }
            height: Theme.barHeight
            spacing: 10

            Workspaces { window: bar }

            Item {
                implicitWidth: 20
                implicitHeight: 20
                Icon {
                    name: Distro.glyph
                    size: 20
                    color: logoArea.containsMouse ? Theme.accentBright : Theme.accent
                }
                MouseArea {
                    id: logoArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Panels.controlOpen = !Panels.controlOpen
                }
            }

            Label {
                id: title
                visible: Config.bar.showWindowTitle
                readonly property real start: (void [x, parent.x, parent.width], mapToItem(null, 0, 0).x)
                readonly property real islandStart: (bar.width - bar.islandWidth) / 2
                    - (Theme.slanted ? Slant.lean(bar.islandHang) : 0) - Theme.shoulder - 14
                Layout.maximumWidth: Math.max(0, islandStart - start)
                elide: Text.ElideRight
                color: Theme.subtext0
                font.pixelSize: Theme.fontSizeSmall + 1
                text: ToplevelManager.activeToplevel?.title ?? ""

                onTextChanged: titleSwap.restart()
                transform: Translate { id: titleShift }
                SequentialAnimation {
                    id: titleSwap
                    PropertyAction { target: title; property: "opacity"; value: 0 }
                    PropertyAction { target: titleShift; property: "y"; value: 6 }
                    ParallelAnimation {
                        Anim { target: title; property: "opacity"; to: 1 }
                        Anim { target: titleShift; property: "y"; to: 0; easing.bezierCurve: Theme.curveDecelerate }
                    }
                }
            }
        }

        RowLayout {
            anchors { right: parent.right; rightMargin: 8 }
            height: Theme.barHeight
            spacing: 2

            Module {
                visible: GameMode.active
                onClicked: GameMode.toggle()
                Icon { name: "gamepad"; size: 16; color: Theme.accent }
            }

            Module {
                visible: Privacy.active
                active: Panels.privacyOpen
                onClicked: Panels.privacyOpen = !Panels.privacyOpen
                Repeater {
                    model: [
                        { on: Privacy.camera || Privacy.screen, color: Theme.green },
                        { on: Privacy.mic, color: Theme.peach },
                    ]
                    Rectangle {
                        required property var modelData
                        visible: modelData.on
                        implicitWidth: 8; implicitHeight: 8; radius: 4
                        color: modelData.color
                        SequentialAnimation on scale {
                            running: modelData.on && Theme.speed > 0
                            loops: 2
                            NumberAnimation { to: 1.5; duration: 220; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 1; duration: 320; easing.type: Easing.OutBack }
                        }
                    }
                }
            }

            Module {
                visible: Gpu.enabled && Gpu.awake
                active: Panels.gpuOpen
                onClicked: Panels.gpuOpen = !Panels.gpuOpen
                Rectangle {
                    implicitWidth: 8; implicitHeight: 8; radius: 4
                    color: Theme.yellow
                    SequentialAnimation on scale {
                        running: Gpu.awake && Theme.speed > 0
                        loops: 2
                        NumberAnimation { to: 1.5; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { to: 1; duration: 320; easing.type: Easing.OutBack }
                    }
                }
            }

            Module {
                visible: Updates.total > 0
                active: Panels.updatesOpen
                onClicked: Panels.updatesOpen = !Panels.updatesOpen
                Icon { name: "package-update"; size: 16; color: Theme.accent }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall + 1; text: Updates.total }
            }

            Module {
                visible: KeepAwake.active
                active: Panels.awakeOpen
                onClicked: Panels.awakeOpen = !Panels.awakeOpen
                Icon { name: KeepAwake.icon; size: 15; color: Theme.accent }
                Label {
                    visible: KeepAwake.minutes > 0
                    mono: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.accent
                    text: KeepAwake.format(KeepAwake.remaining)
                }
            }

            Module {
                visible: Keyboard.multiple
                onClicked: Panels.keyboardOpen = !Panels.keyboardOpen
                onScrolled: Keyboard.next()
                Label {
                    mono: true
                    font.weight: Font.DemiBold
                    font.pixelSize: Theme.fontSizeSmall + 1
                    color: Theme.accent
                    text: Keyboard.code
                }
            }

            Module {
                visible: Recorder.recording
                onClicked: Recorder.stop()
                Rectangle {
                    implicitWidth: 9; implicitHeight: 9; radius: 4.5
                    color: Theme.red
                    SequentialAnimation on opacity {
                        running: Recorder.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 700 }
                        NumberAnimation { to: 1; duration: 700 }
                    }
                }
                Label { mono: true; font.pixelSize: Theme.fontSizeSmall; color: Theme.red; text: Recorder.format(Recorder.seconds) }
            }

            Module {
                visible: Hardware.airplane
                onClicked: Hardware.setAirplane(false)
                Icon { name: "airplane"; color: Theme.accent }
            }
            Module {
                visible: !Hardware.touchpad
                onClicked: Hardware.setTouchpad(true)
                Icon { name: "touchpad-off"; color: Theme.error }
            }
            Module {
                visible: Hardware.hasCameraSwitch && Hardware.cameraKnown && !Hardware.camera
                onClicked: Hardware.cameraKey()
                Icon { name: "camera-off"; color: Theme.overlay1 }
            }

            Module {
                visible: bar.mic?.muted ?? false
                onClicked: bar.mic.muted = false
                Icon { name: "mic-off"; color: Theme.accent }
            }

            Module {
                id: phoneModule
                readonly property var phone: Phone.phone
                visible: Phone.enabled && (phone !== null || Phone.asking.length > 0)
                active: Panels.phoneOpen
                onClicked: Panels.phoneOpen = !Panels.phoneOpen
                Icon { name: "smartphone"; color: Theme.accent }
                Label {
                    visible: (phoneModule.phone?.battery ?? -1) >= 0
                    mono: true
                    font.pixelSize: Theme.fontSizeSmall + 1
                    color: phoneModule.phone?.battery <= 20 && !phoneModule.phone?.charging ? Theme.warning : Theme.text
                    text: phoneModule.phone?.battery ?? ""
                }
                readonly property int level: phone && !phone.charging ? phone.battery : -1
                onLevelChanged: {
                    if (level >= 0 && level <= 15 && !lowWarned) {
                        lowWarned = true;
                        Activities.banner("smartphone", phone.name + " · " + level + "%", Tr.t("The phone's battery is low"), level / 100, Theme.warning, 5000);
                    } else if (level > 20 || level < 0) lowWarned = false;
                }
                property bool lowWarned: false
            }

            Module {
                id: btModule
                visible: Bluetooth.defaultAdapter?.enabled ?? false
                active: Panels.bluetoothOpen
                onClicked: Panels.bluetoothOpen = !Panels.bluetoothOpen
                readonly property var withBattery: (Bluetooth.defaultAdapter?.devices.values ?? []).find(d => d.connected && d.batteryAvailable) ?? null
                readonly property int level: withBattery && withBattery.battery > 0 ? Math.round(withBattery.battery * 100) : -1
                Icon {
                    name: btModule.withBattery && /audio|headset|headphone/.test(btModule.withBattery.icon ?? "") ? "headphones" : "bluetooth"
                    color: Theme.accent
                }
                Label {
                    visible: btModule.level >= 0
                    mono: true
                    font.pixelSize: Theme.fontSizeSmall + 1
                    color: btModule.level <= 20 ? Theme.warning : Theme.text
                    text: btModule.level
                }
                onLevelChanged: {
                    if (level >= 0 && level <= 15 && !lowWarned) {
                        lowWarned = true;
                        Activities.banner("headphones", (withBattery?.name || withBattery?.deviceName || Tr.t("Bluetooth")) + " · " + level + "%",
                            Tr.t("Bluetooth battery is low"), level / 100, Theme.warning, 5000);
                    } else if (level > 20) lowWarned = false;
                }
                property bool lowWarned: false
            }

            Module {
                id: netModule
                visible: bar.wifiDevice !== null && Networking.wifiEnabled && !(bar.wired && !bar.wifiNetwork)
                active: Panels.wifiOpen
                onClicked: Panels.wifiOpen = !Panels.wifiOpen

                Icon {
                    name: Networking.wifiEnabled && bar.wifiNetwork ? "wifi" : "wifi-off"
                    color: bar.wifiNetwork ? Theme.accent : Theme.overlay1
                    level: Icons.wifiLevel(bar.wifiNetwork?.signalStrength ?? 0)
                }
                Label {
                    visible: bar.wifiNetwork !== null
                    Layout.maximumWidth: 120
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: bar.wifiNetwork?.name ?? ""
                }
            }

            Module {
                visible: bar.wired && !bar.wifiNetwork
                onClicked: Panels.controlOpen = !Panels.controlOpen
                Icon { name: "ethernet"; color: Theme.accent }
                Label { font.pixelSize: Theme.fontSizeSmall + 1; text: Tr.t("Wired") }
            }

            Divider { visible: Battery.available }

            Module {
                id: batteryModule
                visible: Battery.available
                active: Panels.batteryOpen
                onClicked: Panels.batteryOpen = !Panels.batteryOpen
                readonly property color tint: Battery.charging ? Theme.accent
                    : Battery.percent <= 15 ? Theme.error
                    : Battery.percent <= 30 ? Theme.warning : Theme.accent

                BatteryGlyph {
                    percent: Battery.percent
                    size: 22
                    color: batteryModule.tint
                }
                Label {
                    mono: true
                    font.pixelSize: Theme.fontSizeSmall + 1
                    text: Battery.percent + "%"
                }
            }
        }
    }

    Edges { id: edges }
}
