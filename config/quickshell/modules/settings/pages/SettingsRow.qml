import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

RowLayout {
    id: r
    property string title
    readonly property bool isOption: true
    property real flash: 0
    SequentialAnimation on flash {
        id: flashAnim
        running: false
        NumberAnimation { to: 1; duration: Theme.paced(180) }
        PauseAnimation { duration: Theme.paced(900) }
        NumberAnimation { to: 0; duration: Theme.paced(700) }
    }
    function highlight() { flashAnim.restart(); }
    default property alias control: slot.data
    Layout.fillWidth: true
    spacing: Theme.space16
    Label {
        Layout.fillWidth: true
        text: r.title
        font.weight: Font.DemiBold
        color: Qt.rgba(Theme.text.r + (Theme.accentInk.r - Theme.text.r) * r.flash,
                       Theme.text.g + (Theme.accent.g - Theme.text.g) * r.flash,
                       Theme.text.b + (Theme.accent.b - Theme.text.b) * r.flash, 1)
    }
    Item {
        id: slot
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        implicitWidth: children.length > 0 ? children[0].implicitWidth : 0
        implicitHeight: Math.max(30, childrenRect.height)
    }
}
