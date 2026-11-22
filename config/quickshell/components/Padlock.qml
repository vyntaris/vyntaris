import QtQuick
import qs.config

// A padlock whose shackle lifts and swings out from its right leg as `open` goes from 0 to 1. Drawn at 14 by 18
// and scaled to `size` (its height), so it stays crisp in the bar and big in a dialog.
Item {
    id: root
    property real open: 0
    property color color: Theme.accentInk
    property real size: 18
    width: 14 * size / 18
    height: size

    Item {
        width: 14; height: 18
        scale: root.size / 18
        transformOrigin: Item.TopLeft
        Rectangle {
            x: 2; width: 10; height: 12; radius: 5
            y: 1 - root.open * 4
            color: "transparent"
            border { width: 2; color: root.color }
            transform: Rotation { origin.x: 9; origin.y: 12; angle: -28 * root.open }
        }
        Rectangle {
            y: 8; width: 14; height: 10; radius: 3
            color: root.color
        }
    }
}
