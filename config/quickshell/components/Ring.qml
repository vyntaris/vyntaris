import QtQuick
import QtQuick.Shapes
import qs.config

Item {
    id: root
    property real value: 0
    property color color: Theme.accent
    property real thickness: 5
    property string text: ""
    property string caption: ""

    implicitWidth: 58
    implicitHeight: 58

    readonly property real shown: Math.max(0, Math.min(1, value))
    property real animated: shown
    Behavior on animated { Anim { duration: Theme.durationSlow } }

    component Arc: ShapePath {
        property real sweep
        fillColor: "transparent"
        strokeWidth: root.thickness
        strokeStyle: ShapePath.DashLine
        dashPattern: [1.1, 0.7]
        capStyle: ShapePath.FlatCap
        PathAngleArc {
            centerX: root.width / 2; centerY: root.height / 2
            radiusX: root.width / 2 - root.thickness; radiusY: root.height / 2 - root.thickness
            startAngle: 135; sweepAngle: sweep
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        Arc { strokeColor: Theme.alpha(Theme.text, 0.1); sweep: 270 }
        Arc { strokeColor: root.color; sweep: 270 * root.animated }
    }

    Column {
        anchors.centerIn: parent
        spacing: -1
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            mono: true
            font.pixelSize: Theme.fontSizeSmall + 1
            font.weight: Font.DemiBold
            text: root.text
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            caps: true
            font.pixelSize: Theme.fontSizeSmall - 3
            color: Theme.overlay1
            text: root.caption
        }
    }
}
