import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root
    property int maxRows: 5
    signal chosen()
    spacing: 8

    SearchField {
        id: search
        Layout.fillWidth: true
        placeholder: Tr.t("A city…")
        onTextChanged: Weather.search(text)
        onAccepted: if (list.model.length) list.pickRow(list.model[0].value)
    }
    PickList {
        id: list
        maxRows: root.maxRows
        current: Config.weather.city ? "picked" : "zone"
        function pickRow(v) {
            if (v === "zone") Weather.choose(null);
            else if (v !== "picked") Weather.choose(Weather.found[Number(v)]);
            search.text = "";
            root.chosen();
        }
        model: search.text.trim().length < 2
            ? [{ value: "zone", title: Tr.t("From the time zone"), caption: TimeZone.current ? TimeZone.city(TimeZone.current) : "" }]
                .concat(Config.weather.city ? [{ value: "picked", title: Config.weather.city, caption: Tr.t("Picked") }] : [])
            : Weather.found.map((p, i) => ({ value: String(i), title: p.name, caption: [p.region, p.country].filter(x => x).join(", ") }))
        onPicked: v => pickRow(v)
    }
    Label {
        visible: search.text.trim().length >= 2 && Weather.found.length === 0
        leftPadding: 14
        color: Theme.overlay1
        text: Weather.looking ? Tr.t("Looking…") : Tr.t("Nothing by that name")
    }
}
