pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

Singleton {
    id: root

    readonly property bool enabled: Config.weather.enabled
    property string city: ""
    property real lat: NaN
    property real lon: NaN
    property var now: null
    property real readAt: 0
    readonly property bool known: enabled && now !== null

    function describe(code, day) {
        if (code === 0) return { icon: day ? "sun" : "moon", text: Tr.t("Clear") };
        if (code <= 2) return { icon: day ? "partly-cloudy" : "partly-cloudy-night", text: Tr.t("Partly cloudy") };
        if (code === 3) return { icon: "cloud", text: Tr.t("Cloudy") };
        if (code === 45 || code === 48) return { icon: "fog", text: Tr.t("Fog") };
        if (code >= 51 && code <= 57) return { icon: "rain", text: Tr.t("Drizzle") };
        if (code >= 61 && code <= 67) return { icon: "rain", text: Tr.t("Rain") };
        if (code >= 71 && code <= 77) return { icon: "snow", text: Tr.t("Snow") };
        if (code >= 80 && code <= 82) return { icon: "rain", text: Tr.t("Showers") };
        if (code === 85 || code === 86) return { icon: "snow", text: Tr.t("Snow showers") };
        if (code >= 95) return { icon: "storm", text: Tr.t("Thunderstorm") };
        return { icon: "cloud", text: "" };
    }

    function refresh() {
        if (!enabled || Date.now() - readAt < 30 * 60000) return;
        const wanted = Config.weather.city.trim();
        if (wanted && (Config.weather.lat !== 0 || Config.weather.lon !== 0)) {
            lat = Config.weather.lat; lon = Config.weather.lon; city = wanted; place = wanted;
            read();
        } else if (wanted) find(wanted);
        else if (!zone.running) zone.running = true;
    }

    property var found: []
    property string searching: ""
    readonly property bool looking: searchLater.running || lookup.running
    function search(text) {
        searching = text.trim();
        if (searching.length < 2) { found = []; return; }
        searchLater.restart();
    }
    Timer {
        id: searchLater
        interval: 250
        onTriggered: {
            lookup.running = false;
            lookup.command = ["curl", "-fsS", "-m", "8", "--get", "--data-urlencode", "name=" + root.searching, "-d", "count=8",
                              "-d", "language=en", "https://geocoding-api.open-meteo.com/v1/search"];
            lookup.running = true;
        }
    }
    Process {
        id: lookup
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.found = (JSON.parse(text).results ?? []).map(r => ({ name: r.name, region: r.admin1 ?? "", country: r.country ?? "",
                                                                             lat: r.latitude, lon: r.longitude }));
                } catch (e) { root.found = []; }
            }
        }
    }
    function choose(p) {
        Config.weather.city = p ? p.name : "";
        Config.weather.lat = p ? p.lat : 0;
        Config.weather.lon = p ? p.lon : 0;
        Config.saveSoon();
        found = [];
    }
    property string place: ""
    function find(name) {
        if (name === place && !isNaN(lat)) { read(); return; }
        place = name;
        geo.command = ["curl", "-fsS", "-m", "10", "--get", "--data-urlencode", "name=" + name, "-d", "count=1",
                       "https://geocoding-api.open-meteo.com/v1/search"];
        geo.running = true;
    }
    function read() {
        if (isNaN(lat) || forecast.running) return;
        forecast.command = ["curl", "-fsS", "-m", "10", "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
            + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1"];
        forecast.running = true;
    }

    Process {
        id: zone
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: {
                const z = text.trim();
                if (z.includes("/")) root.find(z.slice(z.lastIndexOf("/") + 1).replace(/_/g, " "));
            }
        }
    }
    Process {
        id: geo
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text).results?.[0];
                    if (!r) return;
                    root.lat = r.latitude;
                    root.lon = r.longitude;
                    root.city = r.name;
                    root.read();
                } catch (e) {}
            }
        }
    }
    Process {
        id: forecast
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.now = { temp: Math.round(d.current.temperature_2m), code: d.current.weather_code, day: d.current.is_day === 1,
                                 max: Math.round(d.daily.temperature_2m_max[0]), min: Math.round(d.daily.temperature_2m_min[0]) };
                    root.readAt = Date.now();
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Config.weather
        function onCityChanged() { root.readAt = 0; root.lat = NaN; root.place = ""; root.now = null; cityLater.restart(); }
        function onEnabledChanged() { if (root.enabled) { root.readAt = 0; root.refresh(); } else root.now = null; }
    }
    Timer { id: cityLater; interval: 1500; onTriggered: root.refresh() }
    Timer { running: true; interval: 8000; onTriggered: root.refresh() }
}
