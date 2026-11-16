import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// Slanted panel (skwd-style). Each side edge has its own lean:
//   skewL / skewR > 0  lean like "/"  (top edge shifted right of the bottom edge)
//   skewL / skewR < 0  lean like "\"  (top edge shifted left of the bottom edge)
// `skew` sets both at once (a plain parallelogram). Examples:
//   skew:  14                       parallelogram leaning "/"   (cards, small buttons)
//   skewL: 0,  skewR: -14           straight outer edge, inner edge "\"  (left panel, on the screen edge)
//   skewL: 14, skewR: 0             inner edge "/", straight outer edge  (right panel, on the screen edge)
//   skewL: -14, skewR: 14           trapezoid, wider at the top (centre island)
// Children go in the content area. Set strokeWidth: 0 for a stroke-less shape.
Item {
    id: root

    property real skew: 14
    property real skewL: skew
    property real skewR: skew
    property color fill: Theme.bg
    property color stroke: Theme.accentContainer
    property real strokeWidth: 1.5

    // Which outline edges are stroked. Turn one off where the panel is attached to a screen edge.
    property bool strokeTop: true
    property bool strokeLeft: true
    property bool strokeRight: true

    // Outline gauge: 0..1 draws a bright arc growing up both sides from the bottom-middle until the
    // arcs meet at the top-middle. -1 turns it off. Used for countdowns and volume / brightness popups.
    property real progress: -1
    property color progressColor: Theme.accent
    property real progressWidth: 3
    // false: the arc is anchored at the bottom-middle and grows/shrinks toward the top-middle (levels).
    // true:  anchored at the top-middle and grows/shrinks toward the bottom-middle (countdowns, where the
    //        bottom disappears first and the remainder retreats to the top).
    property bool gaugeFromTop: false

    // Frosted glass: a blurred copy of the wallpaper (aligned to the screen) shows through the fill.
    // The panel must be a direct child of its window; tell it where that window sits on the screen.
    property bool glass: false
    property real glassOriginX: 0
    property real glassOriginY: 0
    property real glassTint: 0.55          // how much of the normal fill stays on top of the glass
    readonly property bool glassActive: glass && Theme.glass && Theme.wallpaper !== "" && wall.status === Image.Ready
    readonly property color shownFill: glassActive ? Qt.rgba(fill.r, fill.g, fill.b, fill.a * glassTint) : fill

    default property alias content: holder.data

    readonly property bool gauge: progress >= 0
    readonly property color edgeColor: gauge ? Qt.rgba(stroke.r, stroke.g, stroke.b, 0.28) : stroke

    // Corner points (inset by half the stroke so the stroke isn't clipped; no inset on unstroked edges).
    readonly property real p: strokeWidth / 2
    readonly property real inL: strokeLeft ? p : 0
    readonly property real inR: strokeRight ? p : 0
    readonly property real tlx: skewL > 0 ? skewL : inL
    readonly property real blx: skewL > 0 ? inL : Math.max(inL, -skewL)
    readonly property real trx: skewR > 0 ? width - inR : Math.min(width - inR, width + skewR)
    readonly property real brx: skewR > 0 ? width - skewR : width - inR
    readonly property real ty: strokeTop ? p : 0
    readonly property real by: height - p

    // Gauge geometry: the middle of the bottom and top edges, and the length of each half outline.
    readonly property real midBottom: (blx + brx) / 2
    readonly property real midTop: (tlx + trx) / 2
    readonly property real halfRight: (brx - midBottom) + Math.hypot(trx - brx, by - ty) + (trx - midTop)
    readonly property real halfLeft: (midBottom - blx) + Math.hypot(tlx - blx, by - ty) + (midTop - tlx)

    Behavior on fill { ColorAnimation { duration: 400 } }
    Behavior on stroke { ColorAnimation { duration: 400 } }

    // ---- Frosted glass layer (under the fill) ----
    // One shader (shaders/glass.frag, built with qsb) samples the wallpaper aligned to the screen, blurs it and
    // cuts it to this panel's slanted outline.
    Image {
        id: wall
        x: -100000          // parked off-screen (an invisible Image would not upload its texture)
        source: root.glass && Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
        sourceSize.width: 1280
        sourceSize.height: 720
        asynchronous: true
        cache: true
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.glassActive
        property variant src: wall
        property vector2d itemSize: Qt.vector2d(width, height)
        property vector4d edges: Qt.vector4d(root.tlx, root.blx, root.trx, root.brx)
        property vector2d yRange: Qt.vector2d(root.ty, root.by)
        property vector2d origin: Qt.vector2d(root.x + root.glassOriginX, root.y + root.glassOriginY)
        property vector2d screenSize: Qt.vector2d(Screen.width, Screen.height)
        property vector2d imageSize: Qt.vector2d(Math.max(1, wall.implicitWidth), Math.max(1, wall.implicitHeight))
        fragmentShader: "shaders/glass.frag.qsb"
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        // Fill
        ShapePath {
            fillColor: root.shownFill
            strokeColor: "transparent"
            strokeWidth: -1

            startX: root.tlx;               startY: root.ty
            PathLine { x: root.trx;         y: root.ty }
            PathLine { x: root.brx;         y: root.by }
            PathLine { x: root.blx;         y: root.by }
            PathLine { x: root.tlx;         y: root.ty }
        }

        // Outline, one path per edge so edges attached to the screen can be left out.
        // (dimmed while the gauge arc is drawing on top)
        ShapePath {   // top
            readonly property bool on: root.strokeWidth > 0 && root.strokeTop
            fillColor: "transparent"
            strokeColor: on ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.tlx; startY: root.ty
            PathLine { x: root.trx; y: root.ty }
        }
        ShapePath {   // right
            readonly property bool on: root.strokeWidth > 0 && root.strokeRight
            fillColor: "transparent"
            strokeColor: on ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.trx; startY: root.ty
            PathLine { x: root.brx; y: root.by }
        }
        ShapePath {   // bottom (always)
            fillColor: "transparent"
            strokeColor: root.strokeWidth > 0 ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.brx; startY: root.by
            PathLine { x: root.blx; y: root.by }
        }
        ShapePath {   // left
            readonly property bool on: root.strokeWidth > 0 && root.strokeLeft
            fillColor: "transparent"
            strokeColor: on ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.blx; startY: root.by
            PathLine { x: root.tlx; y: root.ty }
        }

        // Gauge: two dashed half-outlines running up (or down, see gaugeFromTop) BOTH sides at once; the
        // two arcs meet at the top-middle when they are full.
        ShapePath {   // right half: bottom-middle -> right along the bottom -> up the right edge -> top-middle
            fillColor: "transparent"
            strokeColor: root.gauge ? root.progressColor : "transparent"
            strokeWidth: root.progressWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: ShapePath.DashLine
            dashPattern: [Math.max(0.001, root.progress * root.halfRight / root.progressWidth), root.halfRight / root.progressWidth * 2]

            startX: root.gaugeFromTop ? root.midTop : root.midBottom;   startY: root.gaugeFromTop ? root.ty : root.by
            PathLine { x: root.gaugeFromTop ? root.trx : root.brx;      y: root.gaugeFromTop ? root.ty : root.by }
            PathLine { x: root.gaugeFromTop ? root.brx : root.trx;      y: root.gaugeFromTop ? root.by : root.ty }
            PathLine { x: root.gaugeFromTop ? root.midBottom : root.midTop; y: root.gaugeFromTop ? root.by : root.ty }
        }
        ShapePath {   // left half: mirror image
            fillColor: "transparent"
            strokeColor: root.gauge ? root.progressColor : "transparent"
            strokeWidth: root.progressWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: ShapePath.DashLine
            dashPattern: [Math.max(0.001, root.progress * root.halfLeft / root.progressWidth), root.halfLeft / root.progressWidth * 2]

            startX: root.gaugeFromTop ? root.midTop : root.midBottom;   startY: root.gaugeFromTop ? root.ty : root.by
            PathLine { x: root.gaugeFromTop ? root.tlx : root.blx;      y: root.gaugeFromTop ? root.ty : root.by }
            PathLine { x: root.gaugeFromTop ? root.blx : root.tlx;      y: root.gaugeFromTop ? root.by : root.ty }
            PathLine { x: root.gaugeFromTop ? root.midBottom : root.midTop; y: root.gaugeFromTop ? root.by : root.ty }
        }
    }

    Item { id: holder; anchors.fill: parent }
}
