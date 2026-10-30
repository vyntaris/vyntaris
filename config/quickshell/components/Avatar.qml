import QtQuick
import QtQuick.Effects
import qs.config

Rectangle {
    id: root
    property string name
    property string source
    property int version: 0
    property real size: 40
    readonly property bool hasPicture: image.status === Image.Ready

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: Theme.accent

    Label {
        anchors.centerIn: parent
        visible: !root.hasPicture
        font.pixelSize: root.size * 0.42
        font.weight: Font.DemiBold
        color: Theme.textOnAccent
        text: (root.name || "?").charAt(0).toUpperCase()
    }
    Image {
        id: image
        anchors.fill: parent
        visible: false
        source: root.source ? "file://" + root.source.split("/").map(encodeURIComponent).join("/") + "?v=" + root.version : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        asynchronous: true
        cache: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: width / 2
    }
    MultiEffect {
        anchors.fill: parent
        visible: root.hasPicture
        source: image
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
