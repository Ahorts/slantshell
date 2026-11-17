pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Shared look & feel.
//
// Colours follow your Hyprland theme: matugen writes both Hyprland's border colours
// (~/.config/hypr/hyprland/colors.lua) and this Material You palette from the wallpaper.
// We watch the palette file, so the shell recolours live when it changes.
// (Hyprland's active border colour is this palette's `primary_container`.)
Singleton {
    id: root

    // Current wallpaper (absolute path), kept in sync with the same file matugen reads.
    // Empty = gradient background.
    property string wallpaper: ""
    readonly property string wallpaperPathFile: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/wallpaper/path.txt"

    readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"

    // Defaults are used until/unless the palette file loads.
    property color bg: "#1a1018"
    property color bgAlt: "#271c25"
    property color surface: "#32272f"
    property color fg: "#f0dde9"
    property color fgDim: "#d8c0d0"
    property color accent: "#ffabf2"
    property color accent2: "#c5d57a"
    property color accentContainer: "#f461ea"   // = Hyprland active border
    property color accentText: "#5c005a"
    property color warn: "#ffb4ab"
    property color good: "#c5d57a"

    Behavior on bg { ColorAnimation { duration: 700 } }
    Behavior on bgAlt { ColorAnimation { duration: 700 } }
    Behavior on surface { ColorAnimation { duration: 700 } }
    Behavior on fg { ColorAnimation { duration: 700 } }
    Behavior on fgDim { ColorAnimation { duration: 700 } }
    Behavior on accent { ColorAnimation { duration: 700 } }
    Behavior on accent2 { ColorAnimation { duration: 700 } }
    Behavior on accentContainer { ColorAnimation { duration: 700 } }
    Behavior on accentText { ColorAnimation { duration: 700 } }
    Behavior on warn { ColorAnimation { duration: 700 } }
    Behavior on good { ColorAnimation { duration: 700 } }

    // Frosted-glass panels (blurred wallpaper behind them). Turn off to get flat panels.
    property bool glass: true
    // Lightning on borders (bar panels, island, highlights, and Hyprland window borders via WindowSparks.qml).
    // TEMPORARY demo option: `qs -p <dir> ipc call lightning toggle` (or on/off).
    property bool lightning: true
    property bool windowLightning: true
    // the screen whose island has a face open (dashboard, Wi-Fi/BT): window lightning shares the bar's layer and
    // would draw through it, so it fades out there (WindowSparks.qml)
    property string faceScreen: ""
    // where the right bar panel's front (bottom-left) corner is on screen: Flappy's wire hangs from it
    property real barAnchorX: -1
    property real barAnchorY: 48      // the Hyprland window-border part (WindowSparks.qml)
    // One shared clock for every lightning border, so they all redraw on the same frames (a window then repaints
    // ~25 times a second at most instead of once per bolt). Even ticks are the "resting" rate.
    property int sparkTick: 0
    property int sparkUsers: 0
    Timer { interval: 40; repeat: true; running: root.sparkUsers > 0; onTriggered: root.sparkTick++ }

    readonly property string font: "Sans Serif"
    readonly property int fontSize: 13
    readonly property int radius: 12
    readonly property int spacing: 8

    // Parse a palette (our colors.json, or `matugen --json`) into a flat { name: "#rrggbb" } object, or null.
    function flatten(json) {
        let c;
        try { c = JSON.parse(json); } catch (e) { console.warn("Theme: could not parse colors.json:", e); return null; }
        // `matugen --json` nests colours as { name: { dark: { color }, light: {...}, default: {...} } }; take the
        // dark variant and flatten to { name: "#rrggbb" }.
        if (c.colors) {
            const flat = {};
            for (const k in c.colors) {
                const v = c.colors[k];
                flat[k] = (v.dark ?? v.default ?? v).color ?? v.color;
            }
            c = flat;
        }
        return c;
    }

    // Banded diagonal wipe (see ShardWipe.qml): a wallpaper switch does not recolour the shell at once. It stages
    // the new palette and asks for a wipe; the wipe calls commit() when its bands cover the screen, so the
    // colours change underneath them. If nothing answers, a fallback timer commits anyway.
    property bool wipe: false          // off: a wallpaper switch just fades the colours (see ShardWipe.qml)
    property string pendingJson: ""
    property bool pendingPush: false
    property var wipeColors: []
    signal wipeRequested()
    signal wipeCovered()     // the bands now cover the screen: switch whatever needs hiding

    function apply(json, pushToHyprland) {
        if (!(pushToHyprland && wipe)) { applyNow(json, pushToHyprland); return; }
        const c = flatten(json);
        if (!c) return;
        pendingJson = json;
        pendingPush = pushToHyprland;
        wipeColors = [c.primary_container ?? accentContainer, c.primary ?? accent, c.tertiary ?? accent2];
        wipeRequested();
        commitFallback.restart();
    }

    function commit() {
        if (pendingJson === "") return;
        const j = pendingJson, p = pendingPush;
        pendingJson = "";
        commitFallback.stop();
        applyNow(j, p);
    }

    Timer { id: commitFallback; interval: 1800; onTriggered: root.commit() }

    function applyNow(json, pushToHyprland) {
        const c = flatten(json);
        if (!c) return;
        if (c.surface) bg = c.surface;
        if (c.surface_container) bgAlt = c.surface_container;
        if (c.surface_container_high) surface = c.surface_container_high;
        if (c.on_surface) fg = c.on_surface;
        if (c.on_surface_variant) fgDim = c.on_surface_variant;
        if (c.primary) accent = c.primary;
        if (c.tertiary) { accent2 = c.tertiary; good = c.tertiary; }
        if (c.primary_container) accentContainer = c.primary_container;
        if (c.on_primary) accentText = c.on_primary;
        if (c.error) warn = c.error;

        // Wallpaper switch: also recolour Hyprland's window borders live, with the same mapping as the
        // matugen template (active = primary_container, inactive = surface_container_low). Nothing is
        // written to disk, so a Hyprland config reload brings back whatever colors.lua says.
        if (pushToHyprland && c.primary_container && c.surface_container_low && c.surface) {
            const hex = v => v.replace("#", "");
            hyprColors.command = ["hyprctl", "eval",
                "hl.config({ general = { col = { active_border = \"rgba(" + hex(c.primary_container) + "FF)\", "
                + "inactive_border = \"rgba(" + hex(c.surface_container_low) + "33)\" } }, "
                + "misc = { background_color = \"rgba(" + hex(c.surface) + "FF)\" } })"];
            hyprColors.running = true;
        }
    }

    // Recolour straight from an image, without touching any files or other apps
    // (matugen dry-run). Used by the wallpaper switcher.
    // Recolour for a newly applied wallpaper. If an `ii` (illogical-impulse) setup is present, run its
    // theming script in the background: it rebuilds the system palette and re-themes apps such as kitty,
    // GTK and KDE, and the new palette reaches the shell through the colors.json watcher below.
    // Without it (or if it fails) fall back to a colours-only dry run that needs just `matugen`.
    readonly property string themeScript: Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/colors/switchwall.sh"
    property bool pushPending: false

    function generateFrom(imagePath) {
        pushPending = true;
        themeProc.imagePath = imagePath;
        themeProc.command = ["sh", "-c",
            'if [ -x "$1" ]; then exec "$1" --image "$2" --noswitch; else exit 127; fi',
            "sh", themeScript, imagePath];
        themeProc.running = true;
    }

    Process {
        id: themeProc
        property string imagePath: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) colorsFile.reload();          // make sure the new palette is picked up
            else root.dryRun(themeProc.imagePath);            // no ii script, or it failed
        }
    }

    function dryRun(imagePath) {
        gen.command = ["matugen", "image", imagePath, "--dry-run", "--json", "hex", "--mode", "dark",
                       "--source-color-index", "0", "--type", "scheme-tonal-spot", "--quiet"];
        gen.running = true;
    }
    Process { id: hyprColors }
    Process {
        id: gen
        stdout: StdioCollector { onStreamFinished: root.apply(text, true) }
    }

    FileView {
        id: colorsFile
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.apply(text(), root.pushPending);   // after a wallpaper switch, also recolour Hyprland borders
            root.pushPending = false;
        }
    }

    FileView {
        path: root.wallpaperPathFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaper = text().trim()
    }
}
