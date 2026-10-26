import QtQuick
import qs.config

ColorAnimation {
    duration: Theme.durationFast
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.curveStandard
}
