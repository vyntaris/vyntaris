import QtQuick
import qs.config

// A MouseArea that the keyboard and a screen reader can use too. On Enter or Space
// clicked() carries no mouse event, so a handler that reads one checks for it first.
MouseArea {
    id: root
    property string label
    property int role: Accessible.Button
    property bool checked: false
    property real ringRadius: parent?.radius ?? 0

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    activeFocusOnTab: enabled

    Accessible.role: role
    Accessible.name: label
    Accessible.focusable: enabled
    Accessible.focused: activeFocus
    Accessible.checkable: role === Accessible.CheckBox || role === Accessible.RadioButton
    Accessible.checked: checked
    Accessible.onPressAction: root.clicked(null)

    Keys.onReturnPressed: root.clicked(null)
    Keys.onEnterPressed: root.clicked(null)
    Keys.onSpacePressed: root.clicked(null)

    FocusRing { ringRadius: root.ringRadius }
}
