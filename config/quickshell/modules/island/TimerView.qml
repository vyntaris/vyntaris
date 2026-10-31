import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 460
    readonly property real hang: content.implicitHeight + 26
    readonly property bool active: Panels.timerOpen

    width: fullWidth
    height: Theme.barHeight + hang

    readonly property var tabs: [
        { id: "timer", label: Tr.t("Countdown") },
        { id: "stopwatch", label: Tr.t("Stopwatch") },
    ]
    property string tab: "timer"

    Component.onCompleted: if (active) activeChanged()
    onActiveChanged: {
        if (!active) return;
        if (Panels.timerTab) { tab = Panels.timerTab; Panels.timerTab = ""; }
        else tab = Chrono.timerActive ? "timer" : Chrono.swActive ? "stopwatch" : tab;
        focusTimer.restart();
    }
    Timer { id: focusTimer; interval: 30; onTriggered: keys.forceActiveFocus() }

    Item {
        id: keys
        Keys.onEscapePressed: Panels.timerOpen = false
        Keys.onTabPressed: {
            const i = root.tabs.findIndex(t => t.id === root.tab);
            root.tab = root.tabs[(i + 1) % root.tabs.length].id;
        }
        Keys.onSpacePressed: root.primary()
        Keys.onReturnPressed: root.primary()
    }

    function primary() {
        if (tab === "timer") Chrono.timerActive ? Chrono.toggleTimer() : Chrono.startTimer(300);
        else Chrono.toggleStopwatch();
    }

    PanelHeader {
        icon: "timer"
        title: Tr.t("Timer")
    }

    component Big: Label {
        Layout.alignment: Qt.AlignHCenter
        mono: true
        font.pixelSize: 46
        font.weight: Font.DemiBold
    }

    component Bar_: Meter {
        property color fill: Theme.accent
        Layout.fillWidth: true
        fillColor: fill
    }

    PanelBody {
        id: content

        Choice {
            Layout.fillWidth: true
            stretch: true
            options: root.tabs.map(t => ({ value: t.id, label: t.label }))
            current: root.tab
            onPicked: v => root.tab = v
        }

        ColumnLayout {
            visible: root.tab === "timer"
            Layout.fillWidth: true
            spacing: Theme.space12

            Big {
                text: Chrono.timerActive ? Chrono.formatUp(Chrono.timerLeft) : "0:00"
                color: Chrono.timerActive && !Chrono.timerRunning ? Theme.overlay1 : Theme.text
            }
            Bar_ { value: Chrono.timerProgress; visible: Chrono.timerActive }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Repeater {
                    model: [5, 15, 25]
                    Button {
                        required property int modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: modelData + Tr.t(" min")
                        onClicked: Chrono.timerActive ? Chrono.addTimer(modelData * 60) : Chrono.startTimer(modelData * 60)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Field {
                    id: custom
                    Layout.fillWidth: true
                    mono: true
                    placeholder: Tr.t("Custom time, like 7m 30s")
                    Connections {
                        target: custom.input
                        function onAccepted() {
                            const s = Chrono.parseDuration(custom.text);
                            if (s > 0) { Chrono.startTimer(s); custom.text = ""; keys.forceActiveFocus(); }
                        }
                    }
                }
                Button {
                    visible: Chrono.timerActive
                    icon: Chrono.timerRunning ? "pause" : "play"
                    label: Chrono.timerRunning ? Tr.t("Pause") : Tr.t("Play")
                    primary: true
                    onClicked: Chrono.toggleTimer()
                }
                Button { visible: Chrono.timerActive; icon: "plus"; text: Tr.t("1 min"); onClicked: Chrono.addTimer(60) }
                Button { visible: Chrono.timerActive; icon: "close"; label: Tr.t("Cancel"); onClicked: Chrono.cancelTimer() }
            }
        }

        ColumnLayout {
            visible: root.tab === "stopwatch"
            Layout.fillWidth: true
            spacing: Theme.space14

            Big {
                text: Chrono.format(Chrono.swElapsed, true)
                color: Chrono.swActive && !Chrono.swRunning ? Theme.overlay1 : Theme.text
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space8
                Button {
                    primary: true
                    icon: Chrono.swRunning ? "pause" : "play"
                    text: (Chrono.swRunning ? Tr.t("Pause") : Chrono.swActive ? Tr.t("Resume") : Tr.t("Start"))
                    onClicked: Chrono.toggleStopwatch()
                }
                Button { visible: Chrono.swActive; icon: "refresh"; text: Tr.t("Reset"); onClicked: Chrono.resetStopwatch() }
            }
        }

    }
}
