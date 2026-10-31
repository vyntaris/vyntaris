import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    required property var window

    readonly property var list: Hyprland.workspaces.values
        .filter(w => w.id > 0).sort((a, b) => a.id - b.id)
    readonly property int activeIndex: list.findIndex(w => w.id === (Hyprland.focusedWorkspace?.id ?? -1))

    readonly property var scratchpad: Hyprland.workspaces.values.find(w => w.name === "special:magic") ?? null
    readonly property bool scratchpadShown:
        (Hyprland.focusedMonitor?.lastIpcObject?.specialWorkspace?.name ?? "") === "special:magic"

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (/^activespecial/.test(event.name)) Hyprland.refreshMonitors();
        }
    }

    function icons(ws) {
        const seen = [];
        for (const t of ws.toplevels.values) {
            const id = t.wayland?.appId ?? t.lastIpcObject?.class ?? "";
            if (!id) continue;
            const entry = DesktopEntries.heuristicLookup(id);
            const path = Quickshell.iconPath(entry?.icon ?? id, true);
            if (path && !seen.includes(path)) seen.push(path);
        }
        return seen.slice(0, 3);
    }

    implicitWidth: row.implicitWidth
    implicitHeight: Theme.barHeight - 8
    Behavior on implicitWidth { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }

    Rectangle {
        readonly property Item target: repeater.count > 0 && root.activeIndex >= 0 ? repeater.itemAt(root.activeIndex) : null
        visible: target !== null
        x: target?.x ?? 0
        width: target?.width ?? 0
        height: parent.height
        radius: Theme.r(height / 2)
        color: Theme.accent
        Behavior on x { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
        Behavior on width { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }
    }

    Row {
        id: row
        height: parent.height

        Repeater {
            id: repeater
            model: root.list

            Item {
                id: ws
                required property var modelData
                required property int index
                readonly property bool focused: root.activeIndex === index
                readonly property var appIcons: Config.bar.workspaceIcons ? root.icons(modelData) : []

                width: Math.max(24, content.implicitWidth + 14)
                height: row.height

                scale: 0.4
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; }
                Behavior on scale { Anim { duration: Theme.durationSlow; easing.bezierCurve: Theme.curveSpring } }
                Behavior on opacity { Anim { duration: Theme.durationNormal } }
                Behavior on width { Anim { duration: Theme.durationNormal; easing.bezierCurve: Theme.curveSpring } }

                RowLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: Theme.space4

                    Label {
                        mono: true
                        text: ws.modelData.id
                        font.pixelSize: Theme.fontSizeLabel
                        font.weight: ws.focused ? Font.Bold : Font.Medium
                        color: ws.focused ? Theme.textOnAccent : Theme.subtext1
                    }
                    Repeater {
                        model: ws.appIcons
                        AppIcon {
                            required property string modelData
                            implicitSize: 13
                            source: modelData
                            themed: Config.bar.workspaceIconsAccent
                            opacity: ws.focused ? 1 : 0.7
                        }
                    }
                }

                MouseArea {
                    id: wsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Compositor.focusWorkspace(ws.modelData.id)
                }
            }
        }

        Item {
            visible: root.scratchpad !== null
            width: 22
            height: row.height

            Rectangle {
                anchors.centerIn: parent
                width: root.scratchpadShown ? 10 : 6
                height: width
                radius: width / 2
                color: root.scratchpadShown ? Theme.accent : Theme.overlay1
                Behavior on width { Anim { easing.bezierCurve: Theme.curveSpring } }
                Behavior on color { ColorAnim {} }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Compositor.toggleSpecial("magic")
            }
        }
    }

    WheelHandler {
        onWheel: event => Compositor.cycleWorkspace(event.angleDelta.y > 0 ? -1 : 1)
    }

}
