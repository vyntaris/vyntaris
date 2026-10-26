import QtQuick
import qs.config

NumberAnimation {
    duration: Theme.durationNormal
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.curveStandard
}
