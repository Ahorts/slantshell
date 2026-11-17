import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "widgets"

// The wallpaper switcher's own window (it is not part of the island). Entrance: a bright line shoots across the
// middle of the screen from the centre, then the line opens up and down like a shutter into a see-through band, and
// only then the strip, its cards and the two dials roll in (see WallpaperFace.qml). Closing runs it backwards.
PanelWindow {
    id: win

    property bool open: false
    property int forceTurn: 0
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    // three stages, each on its own timeline
    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
    property real line: wanted ? 1 : 0          // the line shooting across
    Behavior on line {
        SequentialAnimation {
            PauseAnimation { duration: win.wanted ? 0 : 260 }
            NumberAnimation { duration: win.wanted ? 300 : 200; easing.type: Easing.OutCubic }
        }
    }
    property real shutter: wanted ? 1 : 0       // the line opening into the band
    Behavior on shutter {
        SequentialAnimation {
            PauseAnimation { duration: win.wanted ? 240 : 120 }
            SpringAnimation { spring: 3.4; damping: 0.38; epsilon: 0.002 }
        }
    }
    property bool contentOn: false
    Timer { id: contentDelay; interval: 420; onTriggered: win.contentOn = true }
    onWantedChanged: { if (wanted) contentDelay.restart(); else { contentDelay.stop(); contentOn = false; } }

    visible: wanted || dim > 0.002 || line > 0.002 || shutter > 0.002

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-wallpapers"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.5 * win.dim }
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

    Item {
        id: band
        readonly property real fullH: face.faceH
        width: win.width * win.line
        height: Math.max(2, fullH * win.shutter)
        x: (win.width - width) / 2
        y: (win.height - height) / 2
        clip: true

        Rectangle { anchors.fill: parent; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55) }
        MouseArea { anchors.fill: parent }      // clicks on the band do not close it

        WallpaperFace {
            id: face
            width: win.width
            height: faceH
            availW: win.width
            x: (band.width - width) / 2
            y: (band.height - height) / 2
            active: win.contentOn
            forceTurn: win.forceTurn
            opacity: Math.min(1, Math.max(0, win.shutter * 1.6 - 0.4))
            onCloseRequested: win.closeRequested()
        }
        // the two bright edges (the line that split in two), with a current running along them
        Rectangle { width: parent.width; height: 2; y: 0; color: Theme.accent }
        Rectangle { width: parent.width; height: 2; y: parent.height - 2; color: Theme.accent }
        EdgeSpark {
            id: edgeT
            anchors.fill: parent
            visible: win.contentOn
            points: [[0, 1], [band.width, 1]]
            intensity: 0.16
            speed: 0.8
        }
        EdgeSpark {
            id: edgeB
            anchors.fill: parent
            visible: win.contentOn
            points: [[0, band.height - 1], [band.width, band.height - 1]]
            intensity: 0.16
            speed: 0.8
        }
        Connections { target: face; function onSparked(amount) { edgeT.burst(amount * 0.8); edgeB.burst(amount * 0.8); } }
    }
}
