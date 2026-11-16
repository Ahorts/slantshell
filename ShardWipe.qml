import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// Banded diagonal wipe. When the palette changes (wallpaper switch), three stacked slanted bands in the NEW
// palette colours sweep across the whole screen, one after another; when they cover it the new palette is
// committed underneath, then the bands run off the far side. Click-through, Overlay layer.
PanelWindow {
    id: win

    property bool running: false
    property real t: 0                    // 0..1 over the whole wipe
    property bool committed: false
    property var colors: [Theme.accentContainer, Theme.accent, Theme.accent2]

    visible: running
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-wipe"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}

    function start() {
        committed = false;
        running = true;
        sweep.restart();
    }

    Connections {
        target: Theme
        function onWipeRequested() {
            win.colors = Theme.wipeColors;
            win.start();
        }
    }

    NumberAnimation {
        id: sweep
        target: win
        property: "t"
        from: 0
        to: 1
        duration: 1400
        easing.type: Easing.Linear
        onFinished: win.running = false
    }

    // Hand over to the new palette once the bands cover the screen.
    onTChanged: if (!committed && t >= 0.52) { committed = true; Theme.commit(); }

    // Geometry of band i (0 = top): its four corners, leaning "/".
    function band(i) {
        const W = width, H = height;
        const h = H / 3 + 6;
        const y0 = i * (H / 3) - 3, y1 = y0 + h;
        const s = h * 0.32;                                   // how far the top edge leans
        const delay = i * 0.1;
        const p = Math.max(0, Math.min(1, (t - delay) / 0.8));
        const cover = 1 - Math.pow(1 - Math.min(1, p / 0.5), 3);          // ease-out
        const q = Math.max(0, (p - 0.5) / 0.5);
        const exit = q * q * q;                                           // ease-in
        const span = W + 2 * s;
        const L = -s + span * cover;                          // leading edge
        const T = -s + span * exit;                           // trailing edge
        return { tl: Qt.point(T + s, y0), tr: Qt.point(L + s, y0), br: Qt.point(L, y1), bl: Qt.point(T, y1), on: L > T + 0.5 };
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            id: path0
            readonly property var b: win.band(0)
            fillColor: b.on ? win.colors[0] ?? "white" : "transparent"
            strokeWidth: -1
            startX: b.tl.x; startY: b.tl.y
            PathLine { x: path0.b.tr.x; y: path0.b.tr.y }
            PathLine { x: path0.b.br.x; y: path0.b.br.y }
            PathLine { x: path0.b.bl.x; y: path0.b.bl.y }
            PathLine { x: path0.b.tl.x; y: path0.b.tl.y }
        }
        ShapePath {
            id: path1
            readonly property var b: win.band(1)
            fillColor: b.on ? win.colors[1] ?? "white" : "transparent"
            strokeWidth: -1
            startX: b.tl.x; startY: b.tl.y
            PathLine { x: path1.b.tr.x; y: path1.b.tr.y }
            PathLine { x: path1.b.br.x; y: path1.b.br.y }
            PathLine { x: path1.b.bl.x; y: path1.b.bl.y }
            PathLine { x: path1.b.tl.x; y: path1.b.tl.y }
        }
        ShapePath {
            id: path2
            readonly property var b: win.band(2)
            fillColor: b.on ? win.colors[2] ?? "white" : "transparent"
            strokeWidth: -1
            startX: b.tl.x; startY: b.tl.y
            PathLine { x: path2.b.tr.x; y: path2.b.tr.y }
            PathLine { x: path2.b.br.x; y: path2.b.br.y }
            PathLine { x: path2.b.bl.x; y: path2.b.bl.y }
            PathLine { x: path2.b.tl.x; y: path2.b.tl.y }
        }
    }
}
