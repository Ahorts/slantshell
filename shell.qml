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
    // singletons load lazily: touch Idle so the sleep inhibitor starts with the shell
    readonly property bool keepAwake: Idle.inhibit

    property bool launcherOpen: false
    property var launcherOnlyWs: []          // demo: list only windows on these workspaces (empty = all)
    property bool wallpapersOpen: false
    property bool dashboardOpen: false
    property bool powerOpen: false
    // Only one drawer grows out of the island at a time: opening one sends the others back in.
    onDashboardOpenChanged: if (dashboardOpen) { launcherOpen = false; connectivityOpen = false; powerOpen = false; wallpapersOpen = false; }
    onLauncherOpenChanged: if (launcherOpen) { dashboardOpen = false; connectivityOpen = false; powerOpen = false; wallpapersOpen = false; }
    onConnectivityOpenChanged: if (connectivityOpen) { dashboardOpen = false; launcherOpen = false; powerOpen = false; wallpapersOpen = false; }
    onPowerOpenChanged: if (powerOpen) { dashboardOpen = false; launcherOpen = false; connectivityOpen = false; wallpapersOpen = false; }
    onWallpapersOpenChanged: if (wallpapersOpen) { dashboardOpen = false; launcherOpen = false; connectivityOpen = false; powerOpen = false; }
    property bool galaxyOpen: false
    property string galaxyName: ""
    property int galaxySelectTick: 0
    property int galaxyEndTick: 0
    property int galaxyConfirmTick: 0
    property int galaxyCancelTick: 0
    property int galaxyWhereTick: 0
    property string galaxyWhere: ""
    property bool petOn: true
    property bool petAuto: false
    property int petGameOn: 0
    property int petGameOff: 0
    property bool wheelOpen: false
    property int wheelHot: -1
    property int wheelTurn: 0
    property bool connectivityOpen: false
    property int connectivityTab: -1
    property int wallpaperTurn: 0
    // Hard window edges are the default for this shell (square corners, your own border kept).
    // Set to false to leave your Hyprland rounding alone. Toggle live with `ipc call sharp toggle`.
    property bool sharp: true
    property bool flappyAuto: false
    property int flappyUntil: 0
    property int flappyDemo: 0
    property string flappyPhase: "perched"

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

    // TEMPORARY demo option: lightning on borders (bar, island, highlights, Hyprland window borders).
    IpcHandler {
        target: "lightning"
        function toggle(): void { Theme.lightning = !Theme.lightning; }
        function on(): void { Theme.lightning = true; }
        function off(): void { Theme.lightning = false; }
        function status(): string { return (Theme.lightning ? "on" : "off") + " | live bolts: " + Theme.sparkUsers; }
        // the window-border lightning on its own (e.g. off for a recording full of opening windows)
        function windowsOn(): void { Theme.windowLightning = true; }
        function windowsOff(): void { Theme.windowLightning = false; }
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
        function on(): void { root.flappyUntil = 0; root.flappyAuto = true; }
        function off(): void { root.flappyAuto = false; root.flappyUntil = 0; }
        // demo: play itself through n shards, then miss one and fly home (once)
        function demo(n: int): void { root.flappyUntil = Math.max(1, n); root.flappyAuto = true; root.flappyDemo += 1; }
        function phase(): string { return root.flappyPhase; }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
        function isOpen(): bool { return root.launcherOpen; }
        // for recordings: only list windows on these workspaces ("6,7"); "" lists everything again
        function only(list: string): void { root.launcherOnlyWs = list === "" ? [] : list.split(",").map(x => x.trim()); }
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
        target: "wheel"
        function open(): void { root.wheelOpen = true; }
        function close(): void { root.wheelOpen = false; root.wheelHot = -1; }
        function hover(i: int): void { root.wheelHot = i; }
        function turn(): void { root.wheelTurn += 1; }
    }

    // Desktop pet and its game: `pet on|off`, `pet game on|off`, `pet auto on|off`.
    IpcHandler {
        target: "pet"
        function on(): void { root.petOn = true; }
        function off(): void { root.petOn = false; }
        function game(state: string): void { if (state === "on") root.petGameOn += 1; else root.petGameOff += 1; }
        function auto(state: string): void { root.petAuto = state === "on"; }
    }

    // System galaxy. `select <name>`, `end <name>`, `confirm` and `cancel` drive it without a mouse (testing, demos).
    IpcHandler {
        target: "galaxy"
        function toggle(): void { root.galaxyOpen = !root.galaxyOpen; }
        function open(): void { root.galaxyOpen = true; }
        function close(): void { root.galaxyOpen = false; }
        function select(name: string): void { root.galaxyName = name; root.galaxySelectTick += 1; }
        function end(name: string): void { root.galaxyName = name; root.galaxyEndTick += 1; }
        function confirm(): void { root.galaxyConfirmTick += 1; }
        function cancel(): void { root.galaxyCancelTick += 1; }
        // "x,y,holeX,holeY": where that program's bubble and the black hole are on screen (for scripted drags)
        function where(name: string): string { root.galaxyWhere = ""; root.galaxyName = name; root.galaxyWhereTick += 1; return root.galaxyWhere; }
    }

    IpcHandler {
        target: "power"
        function toggle(): void { root.powerOpen = !root.powerOpen; }
        function open(): void { root.powerOpen = true; }
        function close(): void { root.powerOpen = false; }
    }

    IpcHandler {
        target: "connectivity"
        function toggle(): void { root.connectivityOpen = !root.connectivityOpen; }
        function open(): void { root.connectivityOpen = true; }
        function close(): void { root.connectivityOpen = false; }
        function tab(i: int): void { root.connectivityTab = i; }
    }

    // What the corner wheel's buttons do.
    function wheelAction(name) {
        switch (name) {
        case "wallpapers":   root.wallpapersOpen = true; break;
        case "dashboard":    root.dashboardOpen = true; break;
        case "launcher":     root.launcherOpen = true; break;
        case "power":        root.powerOpen = true; break;
        case "galaxy":       root.galaxyOpen = true; break;
        case "pet":          root.petOn = !root.petOn; break;
        case "connectivity": root.connectivityOpen = true; break;
        case "sharp":        root.sharp = !root.sharp; break;
        case "flappy":       root.flappyAuto = !root.flappyAuto; break;
        case "lock":         lockScreen.lock(false); break;
        }
    }

    // `ipc call lyrics info` prints where the current lyrics came from and whether they have word timing.
    IpcHandler {
        target: "lyrics"
        function info(): string {
            return Lyrics.status + " | " + (Lyrics.source || "-") + " | words: " + Lyrics.wordSynced + " | lines: " + Lyrics.lines.length;
        }
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
        function turn(): void { root.wallpaperTurn += 1; }
    }

    // sample lock screen for the demo: `ipc call lock lock` (password), or `ipc call lock test` (also unlocks itself after 2 min)
    LockScreen { id: lockScreen }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            ShardWipe { screen: perScreen.modelData }
            Background {
                id: desk
                screen: perScreen.modelData
                flappyAuto: root.flappyAuto
                flappyUntil: root.flappyUntil
                Connections { target: root; function onFlappyDemoChanged() { desk.flappy.flap(); } }
                Binding { target: root; property: "flappyPhase"; value: desk.flappy.phase; when: desk.screen === Quickshell.screens[0] }
                petOn: root.petOn
                petAuto: root.petAuto
                Connections { target: root; function onPetGameOnChanged() { desk.pet.startGame(); } }
                Connections { target: root; function onPetGameOffChanged() { desk.pet.endGame(); } }
            }
            PowerMenu {
                screen: perScreen.modelData
                open: root.powerOpen
                onCloseRequested: root.powerOpen = false
            }
            LauncherFace {
                screen: perScreen.modelData
                open: root.launcherOpen
                onlyWs: root.launcherOnlyWs
                onCloseRequested: root.launcherOpen = false
            }
            ConnectivityFace {
                screen: perScreen.modelData
                open: root.connectivityOpen
                forceTab: root.connectivityTab
                onCloseRequested: root.connectivityOpen = false
            }
            WallpaperWindow {
                screen: perScreen.modelData
                open: root.wallpapersOpen
                forceTurn: root.wallpaperTurn
                onCloseRequested: root.wallpapersOpen = false
            }
            BarZone { screen: perScreen.modelData }
            WindowSparks { screen: perScreen.modelData }
            Island {
                id: isl
                screen: perScreen.modelData
                face: root.dashboardOpen ? "dashboard" : ""
                onLauncherClicked: root.launcherOpen = !root.launcherOpen
                onConnectivityClicked: root.connectivityOpen = !root.connectivityOpen
                onDashboardClicked: root.dashboardOpen = !root.dashboardOpen
                onFaceCloseRequested: { root.dashboardOpen = false; root.launcherOpen = false; root.connectivityOpen = false; root.powerOpen = false; root.wallpapersOpen = false; }
            }
            Galaxy {
                id: galaxy
                screen: perScreen.modelData
                open: root.galaxyOpen
                onCloseRequested: root.galaxyOpen = false
                Connections { target: root; function onGalaxySelectTickChanged() { galaxy.select(root.galaxyName); } }
                Connections { target: root; function onGalaxyEndTickChanged() { galaxy.askEndByName(root.galaxyName); } }
                Connections { target: root; function onGalaxyConfirmTickChanged() { galaxy.confirm(); } }
                Connections { target: root; function onGalaxyCancelTickChanged() { galaxy.cancel(); } }
                Connections { target: root; function onGalaxyWhereTickChanged() { const w = galaxy.whereIs(root.galaxyName); if (w !== "") root.galaxyWhere = w; } }
            }
            CornerWheel {
                screen: perScreen.modelData
                onAction: name => root.wheelAction(name)
                forceOpen: root.wheelOpen
                forceHot: root.wheelHot
                forceTurn: root.wheelTurn
            }
        }
    }
}
