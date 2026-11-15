pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import QtQuick
import qs.config

Singleton {
    id: root

    property var queue: []
    readonly property var current: queue[0] ?? null
    readonly property int waiting: Math.max(0, queue.length - 1)

    property var history: []
    // A notification's app, brought forward: on Wayland an app can't raise its own window when told it was clicked,
    // so the shell does. Its window by the desktop entry or name the notification gives, or the app started.
    function focusApp(desktopEntry, appName) {
        const want = [desktopEntry, appName].filter(x => x).map(x => String(x).toLowerCase().replace(/\.desktop$/, ""));
        if (want.length === 0) return;
        const short = w => w.split(".").pop();
        const t = Hyprland.toplevels.values.find(t => {
            const c = String(t.lastIpcObject?.class ?? t.wayland?.appId ?? "").toLowerCase();
            return c && want.some(w => c === w || c === short(w) || short(c) === short(w));
        });
        if (t) {
            const address = String(t.address).startsWith("0x") ? t.address : "0x" + t.address;
            Compositor.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
        } else {
            const e = want.map(w => DesktopEntries.byId(w) ?? DesktopEntries.heuristicLookup(w)).find(e => e);
            e?.execute();
        }
    }
    readonly property int maxHistory: 50
    property int unread: 0
    property bool dnd: false

    // In Do Not Disturb an app's own sound (WhatsApp's, Discord's) is muted too: its streams that start as its
    // notification comes, for a few seconds. A call or music it already had playing is left alone.
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream)
    PwObjectTracker { objects: root.dnd || root.stale.length ? root.streams : [] }
    property var firstSeen: ({})
    onStreamsChanged: {
        const now = Date.now(), seen = {};
        for (const n of streams) seen[n.id] = firstSeen[n.id] ?? now;
        firstSeen = seen;
    }
    property var hushApps: []
    property double hushFrom: 0
    property var hushed: []
    // PipeWire hands a gone stream's id to the next one.
    function streamKey(n) { return n.id + "@" + (firstSeen[n.id] ?? 0); }
    // Apps whose muted stream ended before it was unmuted: WirePlumber would start their next one muted.
    property var stale: []

    function streamNames(n) {
        const p = n.properties ?? {};
        if (p["media.class"] !== "Stream/Output/Audio") return [];
        return [p["application.process.binary"], p["application.name"], p["application.id"]].filter(x => x).map(x => String(x).toLowerCase());
    }
    function sameApp(names, keys) {
        return names.some(x => keys.some(k => k.length >= 3 && (x === k || x.includes(k) || k.includes(x))));
    }
    function hush(desktopEntry, appName) {
        const keys = [desktopEntry, appName].filter(x => x).map(x => String(x).toLowerCase().replace(/\.desktop$/, "").split(".").pop());
        if (keys.length === 0) return;
        hushApps = keys;
        hushFrom = Date.now() - 1500;
        hushTimer.restart();
        hushNow();
    }
    function hushNow() {
        for (const n of streams) {
            if (!n.audio || n.audio.muted) continue;
            if ((firstSeen[n.id] ?? 0) < hushFrom && !hushed.some(h => h.key === streamKey(n))) continue;
            const names = streamNames(n);
            if (!sameApp(names, hushApps)) continue;
            n.audio.muted = true;
            hushed = hushed.filter(h => h.key !== streamKey(n)).concat([{ key: streamKey(n), names: names }]);
        }
    }
    function unhush() {
        hushTimer.stop();
        const gone = [];
        for (const h of hushed) {
            const n = streams.find(s => streamKey(s) === h.key);
            if (n?.audio) n.audio.muted = false;
            else if (!n) gone.push(...h.names);
        }
        hushed = hushed.filter(h => streams.some(n => streamKey(n) === h.key));
        stale = stale.concat(gone);
    }
    function unstale() {
        for (const n of streams) {
            if (!n.audio?.muted || (firstSeen[n.id] ?? 0) < Date.now() - 5000) continue;
            const names = streamNames(n);
            if (!sameApp(names, stale)) continue;
            n.audio.muted = false;
            stale = stale.filter(x => !names.includes(x));
        }
    }
    Timer {
        id: hushTimer
        interval: 4000
        onTriggered: root.unhush()
    }
    // A stream's properties come a moment after it does.
    Timer {
        interval: 100
        repeat: true
        running: hushTimer.running || root.stale.length > 0
        onTriggered: hushTimer.running ? root.hushNow() : root.unstale()
    }

    function remove(n) {
        queue = queue.filter(x => x !== n);
    }

    // A notification still open in its app, for one in the list: clicking it does what clicking the pop-up does
    // (VWA opens the chat). Kept until it leaves the list.
    function live(entry) {
        return server.trackedNotifications.values.find(n => n.id === entry.id && n.appName === entry.appName) ?? null;
    }
    function activate(entry) {
        const n = live(entry);
        const def = (n?.actions ?? []).find(a => a.identifier === "default");
        if (def) def.invoke();
        focusApp(entry.desktopEntry, entry.appName);
        opened(entry.id, entry.appName);
    }
    // Opened, from the pop-up or the list: done with, so out of the list.
    function opened(id, appName) {
        history = history.filter(e => !(e.id === id && e.appName === appName));
    }
    // Gone from the list: closed in its app too.
    function forget(entries) {
        for (const e of entries) {
            const n = live(e);
            if (n && !queue.includes(n)) n.dismiss();
        }
    }

    function clearHistory() {
        forget(history);
        history = [];
        unread = 0;
    }

    FileView {
        id: store
        path: Quickshell.statePath("notifications.json")
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                root.history = (saved.history ?? []).map(e => Object.assign({}, e, { time: new Date(e.time) }));
                root.dnd = saved.dnd ?? false;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
    property bool loaded: false
    onHistoryChanged: if (loaded) saveTimer.restart()
    onDndChanged: {
        if (!dnd) unhush();
        if (loaded) saveTimer.restart();
    }
    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: store.setText(JSON.stringify({ dnd: root.dnd, history: root.history }))
    }

    function removeAt(index) {
        forget(history.filter((e, i) => i === index));
        history = history.filter((e, i) => i !== index);
    }

    function removeIndexes(list) {
        forget(history.filter((e, i) => list.includes(i)));
        history = history.filter((e, i) => !list.includes(i));
    }

    function markRead() {
        unread = 0;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: n => {
            if (Activities.pacmanBusy && /timeshift/i.test((n.desktopEntry ?? "") + " " + n.appName + " " + n.summary)) {
                n.dismiss();
                return;
            }
            if (n.hints?.value !== undefined) {
                n.tracked = true;
                Activities.trackProgress(n);
                return;
            }
            const entry = {
                id: n.id, appName: n.appName, appIcon: n.appIcon, summary: n.summary, body: n.body,
                image: n.image, time: new Date(), urgency: n.urgency, desktopEntry: n.desktopEntry ?? "",
            };
            const seen = root.history.some(e => e.id === n.id && e.appName === n.appName && e.summary === n.summary);
            if (!seen) {
                const all = [entry].concat(root.history);
                root.forget(all.slice(root.maxHistory));
                root.history = all.slice(0, root.maxHistory);
                root.unread++;
            }

            const critical = n.urgency === NotificationUrgency.Critical;
            if (root.dnd && !critical) {
                root.hush(n.desktopEntry, n.appName);
                n.dismiss();
                return;
            }
            n.tracked = true;
            n.closed.connect(() => root.remove(n));
            if (Config.theme.sounds)
                Quickshell.execDetached(["pw-play", critical ? Quickshell.shellPath("assets/sounds/notification-urgent.wav") : Config.notificationSoundPath(Config.theme.notificationSound)]);
            root.queue = [n].concat(root.queue);
        }
    }
}
