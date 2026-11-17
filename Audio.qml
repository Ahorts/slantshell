pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Shared audio state: the player that is playing, and live cava levels (0..100, 16 bands, bass first).
// cava only runs while something is playing.
Singleton {
    id: root

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    readonly property bool playing: player !== null
    property var bars: []

    onPlayingChanged: if (!playing) bars = []

    // if cava dies while music plays (killed from outside, crashed), start it again shortly
    Timer { id: revive; interval: 600; onTriggered: if (root.playing) cava.running = true }
    Process {
        id: cava
        running: root.playing
        onExited: if (root.playing) revive.restart()
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(x => x !== "").map(Number);
                if (v.length > 0) root.bars = v;
            }
        }
    }
}
