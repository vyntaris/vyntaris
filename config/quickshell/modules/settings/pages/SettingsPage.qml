import QtQuick
import QtQuick.Layouts
import qs.services

ColumnLayout {
    property string pageId
    visible: Panels.settingsPage === pageId
    Layout.fillWidth: true
    spacing: 11
}
