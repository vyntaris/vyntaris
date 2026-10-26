import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.media

RowLayout {
    id: root
    visible: Config.lock.widgets && (media.visible || notes.visible)
    spacing: 12

    MediaCard {
        id: media
        visible: playing
        implicitWidth: 360
        artSize: 56
    }

    Rectangle {
        id: notes
        visible: Notifications.unread > 0
        implicitWidth: notesRow.implicitWidth + 28
        implicitHeight: 44
        radius: Theme.r(22)
        color: Theme.alpha(Theme.crust, 0.6)
        border { width: 1; color: Theme.glassRim }
        RowLayout {
            id: notesRow
            anchors.centerIn: parent
            spacing: 8
            Icon { name: Notifications.dnd ? "bell-off" : "bell"; size: 15; color: Theme.accent }
            Label {
                font.weight: Font.DemiBold
                text: Notifications.unread + " " + (Notifications.unread === 1 ? "notification" : "notifications")
            }
        }
    }
}
