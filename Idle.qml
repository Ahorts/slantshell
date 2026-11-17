pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Keeps the screen awake (no dimming, locking or suspend from hypridle) while `inhibit` is on, using the
// Wayland idle-inhibit protocol on an invisible, click-through surface (the same trick ii uses).
// The choice is remembered in ~/.local/state/slantshell/idle-inhibit ("1" = on). Default: on.
// IPC: qs -p <dir> ipc call idle toggle|on|off|status
Singleton {
    id: root

    property bool inhibit: true
    property bool loaded: false

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slantshell/idle-inhibit"
        blockLoading: true
        printErrors: false
        onLoaded: { root.inhibit = store.text().trim() !== "0"; root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
    Process { id: mk; command: ["mkdir", "-p", store.path.replace(/\/[^\/]*$/, "")] }

    function set(on) {
        inhibit = on;
        mk.running = true;
        store.setText(on ? "1\n" : "0\n");
    }
    function toggle() { set(!inhibit); }

    IdleInhibitor {
        enabled: root.inhibit
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            anchors { right: true; bottom: true }
            mask: Region {}
        }
    }

    IpcHandler {
        target: "idle"
        function toggle(): void { root.toggle(); }
        function on(): void { root.set(true); }
        function off(): void { root.set(false); }
        function status(): string { return root.inhibit ? "awake (idle inhibited)" : "normal (may sleep)"; }
    }
}
