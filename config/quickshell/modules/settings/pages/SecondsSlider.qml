import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components

RowLayout {
    id: sec
    property int value
    signal edited(int v)
    spacing: Theme.space10
    implicitWidth: 254
    Slider {
        implicitWidth: 180
        value: Math.min(1, sec.value / 3600)
        onMoved: v => sec.edited(Math.round(v * 3600 / 30) * 30)
    }
    Label {
        mono: true
        Layout.preferredWidth: 64
        horizontalAlignment: Text.AlignRight
        text: sec.value <= 0 ? Tr.t("Off") : sec.value < 60 ? sec.value + Tr.t(" s") : Math.round(sec.value / 60) + Tr.t(" min")
    }
}
