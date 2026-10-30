import Quickshell.Networking
import QtQuick
import qs.config
import qs.components
import qs.services
import qs.modules.wifi

Item {
    id: root
    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property real fullWidth: 400
    readonly property real hang: wifi.bodyHeight + 4

    width: fullWidth
    height: Theme.barHeight + hang

    PanelHeader {
        icon: "wifi"
        title: Tr.t("Wi-Fi")
        Switch {
            checked: Networking.wifiEnabled
            onToggled: on => Networking.wifiEnabled = on
        }
    }

    WifiView {
        id: wifi
        y: Theme.barHeight
        width: root.fullWidth
        showHeader: false
        device: root.device
        open: Panels.wifiOpen
    }
}
