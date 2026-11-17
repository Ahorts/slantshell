import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import "widgets"

// Corner dial. Rest the pointer in the bottom-left corner and a quarter dial swings out of it:
//   - a ring of annular sectors, one per action; the hovered one lifts outward and lights up
//   - an indicator arc around the outside that glides between sectors, with tick marks beside it
//   - a core with the time and page dots, and a slanted tag naming the hovered action
// Scroll over it to turn to the second set. It closes shortly after the pointer leaves.
// Only the corner (closed) or the dial (open) takes the pointer; the rest of the window is click-through.
PanelWindow {
    id: win

    signal action(string name)

    // Open/close without the pointer (used by `ipc call wheel open|close`).
    function show(v) { open = v; }

    readonly property real wheelR: 300      // radius of the area that takes the pointer
    readonly property real r1: 132          // inner radius of the sectors
    readonly property real r2: 244          // outer radius of the sectors
    property bool open: false
    property bool forceOpen: false
    property int forceTurn: 0          // each change turns the dial to the other set (`ipc call wheel turn`)
    onForceTurnChanged: if (open && !flip.running) flip.restart()
    property int forceHot: -1          // highlight a sector without the pointer (`ipc call wheel hover N`)
    onForceHotChanged: hot = forceHot
    onForceOpenChanged: open = forceOpen
    property real shown: open ? 1 : 0
    Behavior on shown { NumberAnimation { duration: open ? 560 : 260; easing.type: open ? Easing.OutCubic : Easing.InCubic } }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-wheel"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; bottom: true }
    implicitWidth: 380
    implicitHeight: 380
    color: "transparent"

    // closed: a 4px corner; open: the quarter disc (an ellipse centred on the corner)
    mask: Region {
        x: win.open ? -win.wheelR : 0
        y: win.open ? win.height - win.wheelR : win.height - 4
        width: win.open ? 2 * win.wheelR : 4
        height: win.open ? 2 * win.wheelR : 4
        shape: win.open ? RegionShape.Ellipse : RegionShape.Rect
    }

    HoverHandler { id: hover }
    Timer { interval: 90;  running: hover.hovered && !win.open; onTriggered: win.open = true }
    Timer { interval: 360; running: !hover.hovered && win.open && !win.forceOpen; onTriggered: win.open = false }

    // ---- the actions: two pages, scrolling turns to the other one ----
    readonly property var pages: [
        [
            { name: "wallpapers", label: "Wallpapers",   icon: "󰋩" },
            { name: "dashboard",  label: "Dashboard",    icon: "󰕮" },
            { name: "launcher",   label: "Apps",         icon: "󰀻" },
            { name: "lock",       label: "Lock",         icon: "󰌾" },
            { name: "power",      label: "Power",        icon: "󰐥" }
        ],
        [
            { name: "connectivity", label: "Wi-Fi & Bluetooth", icon: "󰖩" },
            { name: "sharp",        label: "Hard edges",        icon: "󰆧" },
            { name: "galaxy",       label: "System galaxy",     icon: "󰓅" },
            { name: "pet",          label: "Desktop pet",       icon: "󰄛" },
            { name: "flappy",       label: "Flappy autopilot",  icon: "󰊖" }
        ]
    ]
    property int page: 0
    readonly property var items: pages[page]
    readonly property int n: items.length
    readonly property real span: 90 / n                 // degrees per sector; item 0 sits at the top

    property int hot: -1                                 // hovered sector
    property real spin: 0
    property real ringOpacity: 1

    SequentialAnimation {
        id: flip
        NumberAnimation { target: win; property: "ringOpacity"; to: 0; duration: 140 }
        ScriptAction { script: { win.hot = -1; win.page = (win.page + 1) % win.pages.length; win.spin = -24; win.bump(); rimSpark.burst(0.9); ringSpark.burst(0.7); } }
        ParallelAnimation {
            NumberAnimation { target: win; property: "spin"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            NumberAnimation { target: win; property: "ringOpacity"; to: 1; duration: 260 }
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => { if (win.open && !flip.running) flip.restart(); }
    }

    // angle (degrees, 0 = along the bottom edge, 90 = up the left edge) -> point around the corner
    function px(a, r) { return r * Math.cos(a * Math.PI / 180); }
    function py(a, r) { return -r * Math.sin(a * Math.PI / 180); }
    // the same, for the full-size Shapes below (their origin is (0, -wheelR), so y is measured from there)
    function sy(a, r) { return wheelR + py(a, r); }
    // a quarter circle of radius r as a polyline, in the full-size Shapes' coordinates (for the rim lightning)
    function quarter(r) {
        const pts = [];
        for (let i = 0; i <= 36; i++) { const a = i * 2.5; pts.push([px(a, r), sy(a, r)]); }
        return pts;
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // The tick ring is alive: it drifts slowly around the dial while the dial is open, and every time you scroll
    // to the other set of actions it jumps forward (a decaying kick) as if the dial had been turned.
    property real drift: 0
    property real kick: 0
    FrameAnimation {
        running: win.shown > 0.01
        onTriggered: win.drift += frameTime * 7          // degrees per second
    }
    NumberAnimation { id: kickAnim; target: win; property: "kick"; duration: 700; easing.type: Easing.OutCubic }
    function bump() { kickAnim.stop(); kickAnim.from = kick; kickAnim.to = kick + 54; kickAnim.start(); }

    // the indicator that glides between sectors (degrees)
    property real indA0: 0
    property real indA1: 0
    property real indOn: 0
    Behavior on indA0 { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
    Behavior on indA1 { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
    Behavior on indOn { NumberAnimation { duration: 220 } }
    onHotChanged: {
        if (hot >= 0) {
            const top = 90 - hot * span;
            indA1 = top - 1.5;
            indA0 = top - span + 1.5;
            indOn = 1;
        } else indOn = 0;
    }

    // ---- everything is drawn around the bottom-left corner ----
    Item {
        id: wheel
        x: 0
        y: win.height
        width: 1
        height: 1
        scale: 0.6 + 0.4 * win.shown
        opacity: Math.min(1, win.shown * 2)
        transformOrigin: Item.TopLeft
        visible: win.shown > 0.01

        // backdrop: a quarter disc with a soft radial falloff
        Shape {
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.7)
                strokeWidth: 1.5
                fillGradient: RadialGradient {
                    centerX: 0; centerY: win.wheelR
                    centerRadius: win.wheelR
                    focalX: 0; focalY: win.wheelR
                    GradientStop { position: 0.0;  color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.97) }
                    GradientStop { position: 0.8;  color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.9) }
                    GradientStop { position: 1.0;  color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.78) }
                }
                startX: 0; startY: win.wheelR
                PathLine { x: win.wheelR - 1; y: win.wheelR }
                PathArc { x: 0; y: 1; radiusX: win.wheelR - 1; radiusY: win.wheelR - 1; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: win.wheelR }
            }
        }

        // fine concentric rings
        Shape {
            id: rings
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            layer.enabled: true
            layer.samples: 4
            opacity: 0.9

            // rim of the core
            ShapePath {
                strokeColor: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.55)
                strokeWidth: 1
                fillColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)
                startX: win.r1 - 12; startY: win.wheelR
                PathArc { x: 0; y: win.wheelR - (win.r1 - 12); radiusX: win.r1 - 12; radiusY: win.r1 - 12; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: win.wheelR }
                PathLine { x: win.r1 - 12; y: win.wheelR }
            }
            // thin ring just outside the sectors
            ShapePath {
                strokeColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.16)
                strokeWidth: 1
                fillColor: "transparent"
                startX: win.r2 + 22; startY: win.wheelR
                PathArc { x: 0; y: win.wheelR - (win.r2 + 22); radiusX: win.r2 + 22; radiusY: win.r2 + 22; direction: PathArc.Counterclockwise }
            }
        }

        // lightning on the rim: a faint current runs round the outer edge and the ring outside the sectors, and
        // flares up when you scroll the dial to the other page
        EdgeSpark {
            id: rimSpark
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            points: win.quarter(win.wheelR - 1.5)
            intensity: 0.2
            speed: 0.8
        }
        EdgeSpark {
            id: ringSpark
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            points: win.quarter(win.r2 + 22)
            intensity: 0.08
            speed: 1.2
        }

        // tick marks: they march around the rim (drift) and jump when the page turns (kick); they fade in and out
        // at the two ends of the quarter so they seem to come from behind the screen edges
        Repeater {
            model: 32
            Rectangle {
                required property int index
                readonly property real a: (((index * 3 + win.drift + win.kick) % 96) + 96) % 96 - 3
                readonly property bool major: index % 5 === 0
                readonly property real edge: Math.max(0, Math.min(1, a / 9)) * Math.max(0, Math.min(1, (90 - a) / 9))
                width: major ? 14 : 7
                height: major ? 2 : 1.5
                x: win.px(a, win.r2 + 22)
                y: win.py(a, win.r2 + 22)
                rotation: -a
                transformOrigin: Item.Left
                color: major ? Theme.accent : Theme.fg
                opacity: (major ? 0.7 : 0.26) * edge * Math.min(1, win.shown * 1.5)
                visible: edge > 0.01
            }
        }

        // sectors
        Item {
            id: ring
            opacity: win.ringOpacity
            rotation: win.spin
            transformOrigin: Item.TopLeft

            Repeater {
                model: win.items

                Shape {
                    id: sec
                    required property var modelData
                    required property int index

                    readonly property real topA: 90 - index * win.span
                    readonly property real a0: topA - win.span + 1.6
                    readonly property real a1: topA - 1.6
                    readonly property real mid: (a0 + a1) / 2
                    readonly property bool isHot: win.hot === index

                    // staggered sweep-in, and the lift when hovered
                    readonly property real grow: Math.max(0, Math.min(1, win.shown * 2.2 - index * 0.22))
                    property real lift: isHot ? 1 : 0
                    Behavior on lift { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                    readonly property real ro: win.r1 + (win.r2 - win.r1) * grow + 12 * lift
                    readonly property real ri: win.r1 - 4 * lift

                    x: 0
                    y: -win.wheelR
                    width: win.wheelR
                    height: win.wheelR
                    layer.enabled: true
                    layer.samples: 4
                    opacity: grow

                    ShapePath {
                        fillColor: sec.isHot ? Theme.accent : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.78)
                        strokeColor: sec.isHot ? Theme.accent : Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.8)
                        strokeWidth: 1.2
                        Behavior on fillColor { ColorAnimation { duration: 180 } }

                        startX: win.px(sec.a0, sec.ri); startY: win.sy(sec.a0, sec.ri)
                        PathLine { x: win.px(sec.a0, sec.ro); y: win.sy(sec.a0, sec.ro) }
                        PathArc { x: win.px(sec.a1, sec.ro); y: win.sy(sec.a1, sec.ro); radiusX: sec.ro; radiusY: sec.ro; direction: PathArc.Counterclockwise }
                        PathLine { x: win.px(sec.a1, sec.ri); y: win.sy(sec.a1, sec.ri) }
                        PathArc { x: win.px(sec.a0, sec.ri); y: win.sy(sec.a0, sec.ri); radiusX: sec.ri; radiusY: sec.ri; direction: PathArc.Clockwise }
                    }

                    // icon, kept upright, at the middle of the sector
                    Text {
                        x: win.px(sec.mid, (sec.ri + sec.ro) / 2) - width / 2
                        y: win.sy(sec.mid, (sec.ri + sec.ro) / 2) - height / 2
                        text: sec.modelData.icon
                        color: sec.isHot ? Theme.accentText : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 24 + 6 * sec.lift
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
            }
        }

        // the indicator arc that glides between the sectors
        Shape {
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            opacity: win.indOn * win.ringOpacity
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                strokeColor: Theme.accent
                strokeWidth: 3.5
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                startX: win.px(win.indA0, win.r2 + 12); startY: win.sy(win.indA0, win.r2 + 12)
                PathArc {
                    x: win.px(win.indA1, win.r2 + 12); y: win.sy(win.indA1, win.r2 + 12)
                    radiusX: win.r2 + 12; radiusY: win.r2 + 12
                    direction: PathArc.Counterclockwise
                }
            }
        }

        // core: the time, and which page of actions this is
        Column {
            x: 18
            y: -78
            spacing: 1
            Text {
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 24
                font.weight: Font.Light
            }
            Text {
                text: Qt.formatDateTime(clock.date, "ddd d MMM")
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
            Row {
                spacing: 5
                topPadding: 4
                Repeater {
                    model: win.pages.length
                    Rectangle {
                        required property int index
                        width: win.page === index ? 16 : 6
                        height: 4
                        color: win.page === index ? Theme.accent : Theme.fgDim
                        opacity: win.page === index ? 1 : 0.5
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                }
            }
        }

        // slanted tag naming the hovered action, outside the ring at the sector's angle
        SkewPanel {
            id: tag
            readonly property real midA: win.hot >= 0 ? (90 - win.hot * win.span - win.span / 2) : 45
            readonly property string text: win.hot >= 0 && win.hot < win.n ? win.items[win.hot].label : ""
            property string shownText: ""
            onTextChanged: if (text !== "") shownText = text
            skew: 8
            height: 28
            width: label.implicitWidth + 36
            x: win.px(midA, win.r2 + 50) - 6
            y: win.py(midA, win.r2 + 50) - height / 2
            opacity: win.indOn * win.ringOpacity
            scale: 0.85 + 0.15 * win.indOn
            transformOrigin: Item.Left
            fill: Theme.bg
            stroke: Theme.accent
            strokeWidth: 1.5
            Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

            Text {
                id: label
                anchors.centerIn: parent
                text: tag.shownText
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.italic: true
            }
        }

        // pointer handling: turn the pointer position into a sector (polar maths around the corner)
        MouseArea {
            x: 0
            y: -win.wheelR
            width: win.wheelR
            height: win.wheelR
            hoverEnabled: true
            function sectorAt(mx, my) {
                const dx = mx, dy = win.wheelR - my;
                const r = Math.hypot(dx, dy);
                if (r < win.r1 - 6 || r > win.r2 + 14) return -1;
                const a = Math.atan2(dy, dx) * 180 / Math.PI;      // 0..90
                if (a < 0 || a > 90) return -1;
                return Math.min(win.n - 1, Math.floor((90 - a) / win.span));
            }
            onPositionChanged: mouse => win.hot = sectorAt(mouse.x, mouse.y)
            onExited: win.hot = -1
            onClicked: mouse => {
                const i = sectorAt(mouse.x, mouse.y);
                if (i < 0) return;
                const name = win.items[i].name;
                win.open = false;
                win.hot = -1;
                win.action(name);
            }
        }
    }
}
