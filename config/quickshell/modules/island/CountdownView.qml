import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root
    readonly property real fullWidth: 260
    readonly property real hang: 64

    width: fullWidth
    height: Theme.barHeight + hang

    RowLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -2
        spacing: Theme.space16

        Rectangle {
            implicitWidth: 14; implicitHeight: 14; radius: 7
            color: Theme.red
            SequentialAnimation on opacity {
                running: Recorder.counting && Theme.speed > 0
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.3; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }
        }

        Label {
            id: digit
            mono: true
            font.pixelSize: 44
            font.weight: Font.Bold
            text: Recorder.countdown
            onTextChanged: pop.restart()
            ParallelAnimation {
                id: pop
                NumberAnimation { target: digit; property: "scale"; from: 1.6; to: 1; duration: Theme.durationSlow; easing.type: Easing.OutBack }
                NumberAnimation { target: digit; property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
            }
        }

        ColumnLayout {
            spacing: 0
            Label { overline: true; color: Theme.error; text: Tr.t("Recording in") }
            Label { font.pixelSize: Theme.fontSizeSmall; color: Theme.overlay1; text: Tr.t("Click to cancel") }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Recorder.cancel()
    }
}
