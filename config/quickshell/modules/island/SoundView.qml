import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import "../../components/Icons.js" as Icons

Item {
    id: root
    readonly property real fullWidth: 460
    readonly property real hang: content.implicitHeight + 26
    readonly property bool active: Panels.soundOpen
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [ root.sink, root.source ] }

    width: fullWidth
    height: Theme.barHeight + hang

    Component.onCompleted: AudioDevices.watching = active
    onActiveChanged: AudioDevices.watching = active

    PanelHeader { icon: "volume"; title: Tr.t("Sound") }

    component Current: RowLayout {
        id: cur
        property string kind
        property var device: null
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { caps: true; color: Theme.accent; font.pixelSize: Theme.fontSizeSmall - 1; text: cur.kind }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSize + 6
                font.weight: Font.DemiBold
                text: cur.device?.label ?? Tr.t("None")
            }
            Caption { Layout.fillWidth: true; elide: Text.ElideRight; text: cur.device?.sub ?? "" }
        }
        Icon { name: cur.device?.icon ?? "volume"; size: 26; stroke: 1.6; color: Theme.accent }
    }

    component Other: PanelSurface {
        id: row
        required property var modelData
        property bool isInput: false
        readonly property bool can: modelData.available
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.r(12)
        fill: area.containsMouse && can ? Theme.hover : "transparent"
        opacity: can ? 1 : 0.45
        Behavior on fill { ColorAnim {} }
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 12
            Icon { name: row.modelData.icon; size: 16; color: row.modelData.available ? Theme.text : Theme.overlay1 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { Layout.fillWidth: true; elide: Text.ElideRight; text: row.modelData.label }
                Caption {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    visible: !row.modelData.available
                    text: row.modelData.takenOver ? Tr.t("Off") : Tr.t("Not connected")
                }
            }
            Label {
                visible: area.containsMouse && row.can
                caps: true
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.accent
                text: Tr.t("Use")
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: row.can ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: AudioDevices.pick(row.modelData, row.isInput)
        }
    }

    PanelBody {
        id: content
        spacing: 10

        Current { kind: Tr.t("Output"); device: AudioDevices.outputs.find(e => e.current) ?? null }
        SegmentSlider {
            Layout.fillWidth: true
            icon: root.sink?.audio?.muted ? "volume-x" : "volume"
            iconLevel: Icons.volumeLevel(root.sink?.audio?.volume ?? 0)
            value: root.sink?.audio?.volume ?? 0
            dimmed: root.sink?.audio?.muted ?? false
            valueText: root.sink?.audio?.muted ? "--" : Math.round(shown * 100)
            onMoved: v => { if (root.sink?.audio) root.sink.audio.volume = v; }
            onIconClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater { model: AudioDevices.outputs.filter(e => !e.current); Other {} }
        }

        Rectangle { Layout.fillWidth: true; Layout.topMargin: 2; implicitHeight: 1; color: Theme.hairline }

        Current { kind: Tr.t("Input"); device: AudioDevices.inputs.find(e => e.current) ?? null }
        SegmentSlider {
            Layout.fillWidth: true
            icon: root.source?.audio?.muted ? "mic-off" : "mic"
            value: root.source?.audio?.volume ?? 0
            dimmed: root.source?.audio?.muted ?? false
            valueText: root.source?.audio?.muted ? "--" : Math.round(shown * 100)
            onMoved: v => { if (root.source?.audio) root.source.audio.volume = v; }
            onIconClicked: if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater { model: AudioDevices.inputs.filter(e => !e.current); Other { isInput: true } }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Caption { Layout.fillWidth: true; text: Tr.t("Noise suppression") }
            Label {
                caps: true
                font.pixelSize: Theme.fontSizeSmall - 1
                color: NoiseSuppression.level > 0 ? Theme.accent : Theme.overlay1
                text: NoiseSuppression.installing ? Tr.t("Installing…") : NoiseSuppression.labels[NoiseSuppression.level]
            }
        }
        SegmentSlider {
            Layout.fillWidth: true
            icon: "sliders"
            count: 4
            value: NoiseSuppression.level / 4
            dimmed: NoiseSuppression.level === 0
            valueText: ""
            onMoved: v => NoiseSuppression.set(v * 4)
            onIconClicked: NoiseSuppression.set(NoiseSuppression.level > 0 ? 0 : 2)
        }
        Caption {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: !NoiseSuppression.available && !NoiseSuppression.installing
                ? Tr.t("Turning it on installs RNNoise (noise-suppression-for-voice) once.")
                : Tr.t("Low takes out a hum or a fan; higher steps also silence typing and noise between words.")
        }
    }
}
