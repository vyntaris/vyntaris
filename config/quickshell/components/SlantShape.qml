import QtQuick
import QtQuick.Shapes
import "Slant.js" as Slant

Shape {
    id: root
    property color fill: "transparent"
    property color stroke: "transparent"
    property real strokeWidth: 1
    property real radius: 0
    property var edges: null
    property real pathWidth: width
    property real pathHeight: height

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.fill
        strokeColor: root.stroke
        strokeWidth: root.strokeWidth
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: root.edges ? Slant.path(root.pathWidth, root.pathHeight, root.radius, root.edges) : "" }
    }
}
