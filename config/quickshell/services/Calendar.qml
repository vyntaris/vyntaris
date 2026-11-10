pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import qs.config

// The calendar's events (scripts/calendar.py): kept here, and in Google Calendar once signed in from Calendar.
// Reminders come as notifications: before a timed event, at 9:00 on an all-day one's day.
Singleton {
    id: root

    readonly property string tool: Quickshell.shellPath("scripts/calendar.py")
    property var events: []
    property string google: ""
    property bool syncing: false
    property bool failed: false
    // A Google client is set up (Vyntaris's, or the user's own), so Connect Google can sign in.
    property bool client: false
    property bool connecting: false
    function status() { statusProc.running = false; statusProc.running = true; }
    Process {
        id: statusProc
        command: [root.tool, "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { const s = JSON.parse(text); root.google = s.google ?? ""; root.client = !!s.client; } catch (e) {} }
        }
    }
    // Signing in waits for the browser; signing out forgets the token and Google's events here.
    function connect() { if (!connectProc.running) { connecting = true; connectProc.command = [tool, "connect"]; connectProc.running = true; } }
    function disconnect() { if (!connectProc.running) { connectProc.command = [tool, "disconnect"]; connectProc.running = true; } }
    Process {
        id: connectProc
        onExited: { root.connecting = false; root.status(); root.refresh(); }
    }

    function key(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
    // Events by day ("2026-11-12": [...]), an all-day one on each of its days.
    readonly property var byDay: {
        const out = {};
        for (const e of events) {
            const s = new Date(e.start), end = new Date(e.end);
            const d = new Date(s.getFullYear(), s.getMonth(), s.getDate());
            do {
                (out[key(d)] = out[key(d)] ?? []).push(e);
                d.setDate(d.getDate() + 1);
            } while (e.allDay && d < end);
        }
        for (const k in out) out[k].sort((a, b) => (b.allDay - a.allDay) || a.start.localeCompare(b.start));
        return out;
    }
    function on(d) { return byDay[key(d)] ?? []; }

    function refresh() { listProc.running = false; listProc.running = true; }
    function sync() { if (!syncProc.running) { syncing = true; syncProc.running = true; } }

    // "14:30 Dentist", "Dentist 9", "9am call mum", "Mum's birthday" (all day), on the day picked.
    function parse(text, day) {
        let t = text.trim(), h = -1, m = 0;
        const re = /(?:^|\s)(?:at\s+|u\s+)?(\d{1,2})(?:[:.h](\d{2}))?\s*(am|pm|h)?(?=\s|$)/i;
        const hit = t.match(re);
        if (hit && (hit[2] !== undefined || hit[3] || /^\s*\d/.test(t) || /\s(at|u)\s/i.test(hit[0]))) {
            h = parseInt(hit[1]); m = hit[2] ? parseInt(hit[2]) : 0;
            if (/pm/i.test(hit[3] ?? "") && h < 12) h += 12;
            if (/am/i.test(hit[3] ?? "") && h === 12) h = 0;
            if (h > 23 || m > 59) h = -1;
            else t = (t.slice(0, hit.index) + " " + t.slice(hit.index + hit[0].length)).trim();
        }
        if (!t) return null;
        const pad = n => String(n).padStart(2, "0");
        const date = key(day);
        if (h < 0) return { title: t, start: date + "T00:00", end: date + "T00:00", allDay: true, remind: 0 };
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m);
        const end = new Date(start.getTime() + 3600000);
        const iso = d => key(d) + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes());
        return { title: t, start: iso(start), end: iso(end), allDay: false, remind: 15 };
    }
    function add(text, day) {
        const ev = parse(text, day);
        if (!ev) return false;
        addProc.input = JSON.stringify(ev);
        addProc.running = true;
        return true;
    }
    // An event from the calendar app: {title, start, end, allDay, remind}, new (no id) or changed.
    function save(ev) {
        const p = ev.id ? updProc : addProc;
        if (ev.id) updProc.command = [tool, "update", ev.id];
        p.input = JSON.stringify(ev);
        p.running = true;
    }
    Process {
        id: updProc
        property string input: ""
        stdinEnabled: true
        onStarted: { write(input + "\n"); stdinEnabled = false; }
        onExited: { updProc.stdinEnabled = true; root.refresh(); }
    }

    function remove(id) {
        events = events.filter(e => e.id !== id);
        delProc.command = [tool, "delete", id];
        delProc.running = true;
    }

    // Changed by the Calendar app, or a sync: read again.
    FileView {
        path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/vyntaris/calendar/events.json"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }
    Process {
        id: listProc
        command: [root.tool, "list"]
        stdout: StdioCollector { onStreamFinished: { try { root.events = JSON.parse(text); } catch (e) {} } }
    }
    Process {
        id: syncProc
        command: [root.tool, "sync"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    root.google = s.google ?? "";
                    root.failed = s.error !== undefined;
                } catch (e) {}
            }
        }
        onExited: { root.syncing = false; root.refresh(); }
    }
    Process {
        id: addProc
        property string input: ""
        command: [root.tool, "add"]
        stdinEnabled: true
        onStarted: { write(input + "\n"); stdinEnabled = false; }
        onExited: { addProc.stdinEnabled = true; root.refresh(); }
    }
    Process { id: delProc; onExited: root.refresh() }

    // The shell syncs and reminds; the calendar app (not the leader) only shows.
    Timer { running: Config.leader; repeat: true; interval: 300000; onTriggered: root.sync() }
    Component.onCompleted: { refresh(); status(); if (Config.leader) sync(); }

    // Each minute: what's due to be reminded of since the last look, as a notification.
    property real lastLook: Date.now()
    Timer {
        running: Config.leader
        repeat: true
        interval: 30000
        onTriggered: {
            const now = Date.now();
            for (const e of root.events) {
                if (e.remind < 0) continue;
                const start = new Date(e.start);
                const at = e.allDay ? new Date(start.getFullYear(), start.getMonth(), start.getDate(), 9).getTime()
                    : start.getTime() - e.remind * 60000;
                if (at > root.lastLook && at <= now) {
                    const when = e.allDay ? Tr.t("Today")
                        : e.remind === 0 ? Tr.t("Now") : Tr.f("In {0} min · {1}", e.remind, Qt.formatTime(start, "HH:mm"));
                    Quickshell.execDetached(["notify-send", "-a", Tr.t("Calendar"), "-i", "x-office-calendar", e.title, when]);
                }
            }
            root.lastLook = now;
        }
    }
}
