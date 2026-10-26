pragma Singleton
import Quickshell
import QtQuick
import qs.config

Singleton {
    id: root

    property real now: Date.now()
    Timer {
        interval: 200
        repeat: true
        running: root.timerRunning || root.swRunning
        onTriggered: root.now = Date.now()
    }

    property int timerTotal: 0
    property real timerEnd: 0
    property real timerPausedLeft: -1
    readonly property bool timerActive: timerTotal > 0
    readonly property bool timerRunning: timerActive && timerPausedLeft < 0
    readonly property real timerLeft: !timerActive ? 0
        : timerPausedLeft >= 0 ? timerPausedLeft : Math.max(0, timerEnd - now)
    readonly property real timerProgress: timerActive ? 1 - timerLeft / (timerTotal * 1000) : 0

    function startTimer(seconds) {
        if (!(seconds > 0)) return;
        now = Date.now();
        timerTotal = seconds;
        timerEnd = now + seconds * 1000;
        timerPausedLeft = -1;
    }
    function pauseTimer() {
        if (timerRunning) timerPausedLeft = Math.max(0, timerEnd - Date.now());
    }
    function resumeTimer() {
        if (!timerActive || timerPausedLeft < 0) return;
        now = Date.now();
        timerEnd = now + timerPausedLeft;
        timerPausedLeft = -1;
    }
    function toggleTimer() { timerRunning ? pauseTimer() : resumeTimer(); }
    function cancelTimer() { timerTotal = 0; timerPausedLeft = -1; }
    function addTimer(seconds) {
        if (!timerActive) { startTimer(seconds); return; }
        timerTotal += seconds;
        if (timerPausedLeft >= 0) timerPausedLeft += seconds * 1000;
        else timerEnd += seconds * 1000;
    }

    onTimerLeftChanged: {
        if (timerRunning && timerLeft <= 0) {
            cancelTimer();
            Activities.banner("timer", Tr.t("Time's up"), Tr.t("Timer"), -1, Theme.accent, 6000);
            Activities.chime();
        }
    }

    property real swStart: 0
    property real swAccum: 0
    property bool swRunning: false
    readonly property bool swActive: swRunning || swAccum > 0
    readonly property real swElapsed: swAccum + (swRunning ? now - swStart : 0)

    function toggleStopwatch() {
        now = Date.now();
        if (swRunning) { swAccum += now - swStart; swRunning = false; }
        else { swStart = now; swRunning = true; }
    }
    function resetStopwatch() { swRunning = false; swAccum = 0; }

    function format(ms, tenths) {
        const total = Math.floor(ms / 1000);
        const h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, s = total % 60;
        const mm = h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m);
        return mm + ":" + String(s).padStart(2, "0") + (tenths ? "." + Math.floor(ms / 100) % 10 : "");
    }
    function formatUp(ms) { return format(Math.ceil(ms / 1000) * 1000); }

    function parseDuration(text) {
        const t = String(text).trim().toLowerCase().replace(",", ".");
        if (/^\d+:\d{1,2}$/.test(t)) {
            const p = t.split(":").map(Number);
            return p[0] * 60 + p[1];
        }
        let total = 0, matched = false;
        const re = /(\d+(?:\.\d+)?)\s*(h|hr|hours?|m|min|minutes?|s|sec|seconds?)?/g;
        let m;
        while ((m = re.exec(t)) !== null) {
            if (m[0] === "") { re.lastIndex++; continue; }
            matched = true;
            const v = parseFloat(m[1]), u = m[2] ?? "m";
            total += /^(h|hr|hour)/.test(u) ? v * 3600 : /^(s|sec)/.test(u) ? v : v * 60;
        }
        return matched ? Math.round(total) : 0;
    }
}
