import Quickshell
import Quickshell.Wayland
import QtQuick
import "widgets"

// Desktop widgets layer. It sits on the Bottom layer (above the wallpaper renderer's
// Background layer, below windows) and is transparent, so whatever wallpaper skwd draws
// shows through. Layers on a mirrored output follow the source screen.
PanelWindow {
    id: bg

    property bool flappyAuto: false

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-desktop-widgets"
    exclusionMode: ExclusionMode.Ignore
    // Lets widgets (e.g. the game) take keyboard focus when clicked, without grabbing it otherwise.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // Only the widgets take input; the rest is click-through.
    mask: Region {
        regions: [
            Region { item: leftColumn },
            Region { item: flappy }
        ]
    }

    // Ambient audio spectrum along the bottom (click-through, only visible while music plays)
    SpectrumBars {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    }

    Column {
        id: leftColumn
        anchors { left: parent.left; top: parent.top; leftMargin: 64; topMargin: 96 }
        spacing: 12

        PulseClock {}
    }

    FlappyWidget {
        id: flappy
        auto: bg.flappyAuto
        anchors { right: parent.right; top: parent.top; rightMargin: 48; topMargin: 96 }
    }
}
