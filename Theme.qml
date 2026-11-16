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

    readonly property string font: "Sans Serif"
    readonly property int fontSize: 13
    readonly property int radius: 12
    readonly property int spacing: 8

    function apply(json) {
        let c;
        try { c = JSON.parse(json); } catch (e) { console.warn("Theme: could not parse colors.json:", e); return; }
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
    }

    FileView {
        path: root.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    FileView {
        path: root.wallpaperPathFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.wallpaper = text().trim()
    }
}
