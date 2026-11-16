import Quickshell
import Quickshell.Io
import QtQuick

// slantshell: a quick demo Quickshell desktop. Run with:  qs -p /path/to/slantshell
//
// Launcher / app switcher IPC (bind these to a key in your Hyprland config):
//   qs -p /path/to/slantshell ipc call launcher toggle
// Wallpaper switcher:
//   qs -p /path/to/slantshell ipc call wallpapers toggle
ShellRoot {
    id: root

    property bool launcherOpen: false
    property bool wallpapersOpen: false
    property bool dashboardOpen: false
    property bool frame: true      // the chamfered screen frame; `ipc call frame toggle`
    // Hard window edges are the default for this shell (square corners, your own border kept).
    // Set to false to leave your Hyprland rounding alone. Toggle live with `ipc call sharp toggle`.
    property bool sharp: true
    property bool flappyAuto: false

    // Square window corners (Hyprland can't slant real windows). Your own border is kept.
    // Turning it off reloads the Hyprland config, which restores your own rounding.
    Process { id: hypr }
    Component.onCompleted: if (root.sharp) root.sharpChanged()   // apply the default at startup
    onSharpChanged: {
        hypr.command = root.sharp
            ? ["hyprctl", "eval", "hl.config({ decoration = { rounding = 0 } })"]
            : ["hyprctl", "reload"];
        hypr.running = true;
    }

    IpcHandler {
        target: "sharp"
        function toggle(): void { root.sharp = !root.sharp; }
        function on(): void { root.sharp = true; }
        function off(): void { root.sharp = false; }
    }

    // Lets the desktop Flappy Bird play itself.
    IpcHandler {
        target: "flappy"
        function on(): void { root.flappyAuto = true; }
        function off(): void { root.flappyAuto = false; }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
    }

    // `ipc call wipe test` plays the banded wipe once (it recolours nothing).
    IpcHandler {
        target: "wipe"
        function test(): void {
            Theme.wipeColors = [Theme.accentContainer, Theme.accent, Theme.accent2];
            Theme.wipeRequested();
        }
    }

    IpcHandler {
        target: "frame"
        function toggle(): void { root.frame = !root.frame; }
        function on(): void { root.frame = true; }
        function off(): void { root.frame = false; }
    }

    IpcHandler {
        target: "dashboard"
        function toggle(): void { root.dashboardOpen = !root.dashboardOpen; }
        function open(): void { root.dashboardOpen = true; }
        function close(): void { root.dashboardOpen = false; }
    }

    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.wallpapersOpen = !root.wallpapersOpen; }
        function open(): void { root.wallpapersOpen = true; }
        function close(): void { root.wallpapersOpen = false; }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            ScreenFrame { screen: perScreen.modelData; active: root.frame }
            ShardWipe { screen: perScreen.modelData }
            Background { screen: perScreen.modelData; flappyAuto: root.flappyAuto }
            Island {
                screen: perScreen.modelData
                onLauncherClicked: root.launcherOpen = !root.launcherOpen
                onDashboardClicked: root.dashboardOpen = !root.dashboardOpen
            }
            Dashboard {
                screen: perScreen.modelData
                open: root.dashboardOpen
                onCloseRequested: root.dashboardOpen = false
            }
            WallpaperPicker {
                screen: perScreen.modelData
                open: root.wallpapersOpen
                onCloseRequested: root.wallpapersOpen = false
            }
            Launcher {
                screen: perScreen.modelData
                open: root.launcherOpen
                onCloseRequested: root.launcherOpen = false
            }
        }
    }
}
