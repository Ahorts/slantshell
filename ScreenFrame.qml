import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// A thin accent frame around the whole screen with 45-degree cut (chamfered) corners, matching the hard
// window edges and the slanted bar. Purely decorative: it takes no input and reserves no space. It sits on
// the Top layer and is created before the bar, so the bar panels draw over it.
PanelWindow {
    id: win

    property bool active: true
    property real shown: active ? 1 : 0
    Behavior on shown { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

    visible: shown > 0.01
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-desktop-frame"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}   // click-through

    readonly property real d: 3      // distance from the screen edge
    readonly property real c: 28     // size of the cut corners

    Shape {
        anchors.fill: parent
        opacity: win.shown
        layer.enabled: true
        layer.samples: 4

        // soft glow
        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.2)
            strokeWidth: 7
            joinStyle: ShapePath.MiterJoin
            startX: win.d + win.c;              startY: win.d
            PathLine { x: win.width - win.d - win.c;   y: win.d }
            PathLine { x: win.width - win.d;           y: win.d + win.c }
            PathLine { x: win.width - win.d;           y: win.height - win.d - win.c }
            PathLine { x: win.width - win.d - win.c;   y: win.height - win.d }
            PathLine { x: win.d + win.c;               y: win.height - win.d }
            PathLine { x: win.d;                       y: win.height - win.d - win.c }
            PathLine { x: win.d;                       y: win.d + win.c }
            PathLine { x: win.d + win.c;               y: win.d }
        }
        // crisp line
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.accentContainer
            strokeWidth: 2
            joinStyle: ShapePath.MiterJoin
            startX: win.d + win.c;              startY: win.d
            PathLine { x: win.width - win.d - win.c;   y: win.d }
            PathLine { x: win.width - win.d;           y: win.d + win.c }
            PathLine { x: win.width - win.d;           y: win.height - win.d - win.c }
            PathLine { x: win.width - win.d - win.c;   y: win.height - win.d }
            PathLine { x: win.d + win.c;               y: win.height - win.d }
            PathLine { x: win.d;                       y: win.height - win.d - win.c }
            PathLine { x: win.d;                       y: win.d + win.c }
            PathLine { x: win.d + win.c;               y: win.d }
        }
        // brighter accent on the four cut corners
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.accent
            strokeWidth: 3
            capStyle: ShapePath.SquareCap
            startX: win.d + win.c;                     startY: win.d
            PathLine { x: win.d;                       y: win.d + win.c }
            PathMove { x: win.width - win.d - win.c;   y: win.d }
            PathLine { x: win.width - win.d;           y: win.d + win.c }
            PathMove { x: win.width - win.d;           y: win.height - win.d - win.c }
            PathLine { x: win.width - win.d - win.c;   y: win.height - win.d }
            PathMove { x: win.d + win.c;               y: win.height - win.d }
            PathLine { x: win.d;                       y: win.height - win.d - win.c }
        }
    }
}
