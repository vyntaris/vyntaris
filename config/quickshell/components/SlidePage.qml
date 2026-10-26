import QtQuick
import qs.config

Item {
    id: pg
    property int index: 0
    property int current: 0
    property real slide: 60
    readonly property int offset: index - current

    anchors.fill: parent
    opacity: 0
    visible: opacity > 0.01
    transform: Translate {
        x: pg.offset === 0 ? 0 : pg.offset > 0 ? pg.slide : -pg.slide
        Behavior on x { Anim { duration: Theme.durationSlow; easing.bezierCurve: Theme.curveSpring } }
    }

    states: State {
        name: "shown"
        when: pg.offset === 0
        PropertyChanges { target: pg; opacity: 1 }
    }
    transitions: [
        Transition {
            to: "shown"
            SequentialAnimation {
                PauseAnimation { duration: Theme.durationFast }
                Anim { property: "opacity"; duration: Theme.durationNormal }
            }
        },
        Transition {
            from: "shown"
            Anim { property: "opacity"; duration: Theme.durationFast }
        }
    ]
}
