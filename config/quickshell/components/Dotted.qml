import QtQuick
import QtQuick.Layouts
import qs.config

// Bits of one line with a Dot between them; empty ones are left out. A Caption's look unless told otherwise.
RowLayout {
    id: root
    property var parts: []
    property color color: Theme.overlay1
    property bool caption: true
    spacing: Theme.space6
    Repeater {
        model: root.parts.filter(p => p !== undefined && p !== null && String(p) !== "")
        RowLayout {
            id: part
            required property var modelData
            required property int index
            spacing: root.spacing
            Dot { visible: part.index > 0 }
            Label {
                overline: root.caption
                font.pixelSize: root.caption ? Theme.fontSizeSmall : Theme.fontSize
                color: root.color
                text: part.modelData
            }
        }
    }
}
