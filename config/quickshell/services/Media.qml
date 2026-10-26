pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    readonly property var players: Mpris.players.values
    readonly property var active: players.find(p => p.isPlaying) ?? players[0] ?? null

    signal changed()

    function toggle() {
        if (active?.canTogglePlaying) { active.togglePlaying(); changed(); }
    }
    function next() {
        if (active?.canGoNext) { active.next(); changed(); }
    }
    function previous() {
        if (active?.canGoPrevious) { active.previous(); changed(); }
    }
}
