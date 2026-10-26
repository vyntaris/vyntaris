import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 500
    readonly property real hang: content.implicitHeight + 28
    readonly property bool active: Panels.captureOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var actions: [
        { id: "shot-region", icon: "image", label: Tr.t("Region"), group: "Picture" },
        { id: "shot-screen", icon: "windows", label: Tr.t("Screen"), group: "Picture" },
        { id: "rec-region", icon: "record", label: Tr.t("Region"), group: "Video" },
        { id: "rec-screen", icon: "record", label: Tr.t("Screen"), group: "Video" },
    ]
    property int current: 0

    function take(i) {
        const a = actions[i];
        if (!a) return;
        Panels.captureOpen = false;
        if (a.id === "shot-region") Screenshot.capture("region");
        else if (a.id === "shot-screen") Screenshot.capture("screen");
        else if (a.id === "rec-region") Recorder.start("region");
        else Recorder.start("screen");
    }

    Component.onCompleted: if (active) activeChanged()
    onActiveChanged: if (active) focusTimer.restart()
    Timer { id: focusTimer; interval: 30; onTriggered: keys.forceActiveFocus() }
    Item {
        id: keys
        anchors.fill: parent
        Keys.onEscapePressed: Panels.captureOpen = false
        Keys.onLeftPressed: root.current = (root.current + 3) % 4
        Keys.onRightPressed: root.current = (root.current + 1) % 4
        Keys.onTabPressed: root.current = (root.current + 1) % 4
        Keys.onReturnPressed: Recorder.recording ? Recorder.stop() : root.take(root.current)
        Keys.onEnterPressed: Recorder.recording ? Recorder.stop() : root.take(root.current)
        Keys.onPressed: event => { const n = parseInt(event.text); if (n >= 1 && n <= 4) { root.take(n - 1); event.accepted = true; } }
    }

    PanelHeader {
        icon: "image"
        title: Tr.t("Capture")
        HeaderButton { icon: "folder"; onClicked: { Panels.captureOpen = false; Screenshot.openFolder(); } }
    }

    PanelBody {
        id: content

        RowLayout {
            Layout.fillWidth: true
            visible: Recorder.recording
            spacing: 12
            Rectangle {
                implicitWidth: 12; implicitHeight: 12; radius: 6
                color: Theme.red
                SequentialAnimation on opacity { running: Recorder.recording; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 700 } NumberAnimation { to: 1; duration: 700 } }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { caps: true; color: Theme.red; font.pixelSize: Theme.fontSizeSmall - 1; text: Tr.t("Recording") }
                Label { mono: true; font.pixelSize: Theme.fontSize + 8; font.weight: Font.Light; text: Recorder.format(Recorder.seconds) }
            }
            Button { primary: true; icon: "stop"; text: Tr.t("Stop"); onClicked: { Recorder.stop(); Panels.captureOpen = false; } }
        }

        RowLayout {
            id: options
            Layout.fillWidth: true
            visible: !Recorder.recording
            spacing: 8
            Repeater {
                model: root.actions
                TileSurface {
                    id: opt
                    required property var modelData
                    required property int index
                    Layout.preferredWidth: (content.width - options.Layout.leftMargin - options.Layout.rightMargin - 3 * 8 - 10) / 4
                    Layout.leftMargin: index === 2 ? 10 : 0
                    implicitHeight: 88
                    marked: root.current === index
                    pressScale: 0.96
                    onEntered: root.current = opt.index
                    onActivated: root.take(opt.index)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: opt.modelData.icon
                            size: 24
                            stroke: 1.6
                            color: opt.modelData.group === "Video" ? Theme.red : (opt.marked ? Theme.accent : Theme.subtext0)
                        }
                        Label { Layout.alignment: Qt.AlignHCenter; caps: true; font.pixelSize: Theme.fontSizeSmall - 2; color: Theme.overlay1; text: opt.modelData.group }
                        Label { Layout.alignment: Qt.AlignHCenter; font.weight: Font.DemiBold; text: opt.modelData.label }
                    }
                }
            }
        }

        KeyHints {
            Layout.alignment: Qt.AlignHCenter
            keys: Recorder.recording ? [["↵", "stop"]] : [["← →", "choose"], ["↵", "take"], ["esc", "close"]]
        }
    }
}
