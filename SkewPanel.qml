import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "widgets"

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

    // Rounded bottom corners. 0 is the plain slanted polygon; larger values round both bottom corners, and
    // a radius of half the width (with the height equal to it) makes the whole shape a half disc hanging from the top.
    // Springs animate this, so the island can melt from a pill into a dial.
    property real radiusB: 0
    readonly property bool round: radiusB > 0.5

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

    // Rounded-corner geometry: where each slanted side stops being straight, and the circle-ish corner curves.
    readonly property real rbEff: Math.max(0, Math.min(radiusB, by - ty, (brx - blx) / 2))
    readonly property real fr: (by - ty) > 1 ? (by - ty - rbEff) / (by - ty) : 1
    readonly property real rpx: trx + (brx - trx) * fr      // right side, where the curve starts
    readonly property real rpy: ty + (by - ty) * fr
    readonly property real lpx: tlx + (blx - tlx) * fr      // left side
    readonly property real lpy: rpy
    readonly property real kap: 0.5523                      // cubic approximation of a quarter circle

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
        property real rb: root.rbEff
        fragmentShader: "shaders/glass.frag.qsb"
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        // Fill
        ShapePath {
            fillColor: root.round ? "transparent" : root.shownFill
            strokeColor: "transparent"
            strokeWidth: -1

            startX: root.tlx;               startY: root.ty
            PathLine { x: root.trx;         y: root.ty }
            PathLine { x: root.brx;         y: root.by }
            PathLine { x: root.blx;         y: root.by }
            PathLine { x: root.tlx;         y: root.ty }
        }

        // Rounded version (fill and outline in one closed path), used while radiusB > 0
        ShapePath {
            fillColor: root.round ? root.shownFill : "transparent"
            strokeColor: root.round && root.strokeWidth > 0 ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            joinStyle: ShapePath.RoundJoin

            startX: root.tlx;               startY: root.ty
            PathLine { x: root.trx;         y: root.ty }
            PathLine { x: root.rpx;         y: root.rpy }
            PathCubic {
                x: root.brx - root.rbEff;   y: root.by
                control1X: root.rpx + (root.brx - root.rpx) * root.kap;   control1Y: root.rpy + (root.by - root.rpy) * root.kap
                control2X: root.brx - root.rbEff + root.rbEff * root.kap; control2Y: root.by
            }
            PathLine { x: root.blx + root.rbEff; y: root.by }
            PathCubic {
                x: root.lpx;                y: root.lpy
                control1X: root.blx + root.rbEff - root.rbEff * root.kap; control1Y: root.by
                control2X: root.lpx + (root.blx - root.lpx) * root.kap;   control2Y: root.lpy + (root.by - root.lpy) * root.kap
            }
            PathLine { x: root.tlx;         y: root.ty }
        }

        // Outline, one path per edge so edges attached to the screen can be left out.
        // (dimmed while the gauge arc is drawing on top)
        ShapePath {   // top
            readonly property bool on: root.strokeWidth > 0 && root.strokeTop && !root.round
            fillColor: "transparent"
            strokeColor: on ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.tlx; startY: root.ty
            PathLine { x: root.trx; y: root.ty }
        }
        ShapePath {   // right
            readonly property bool on: root.strokeWidth > 0 && root.strokeRight && !root.round
            fillColor: "transparent"
            strokeColor: on ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.trx; startY: root.ty
            PathLine { x: root.brx; y: root.by }
        }
        ShapePath {   // bottom (always)
            fillColor: "transparent"
            strokeColor: root.strokeWidth > 0 && !root.round ? root.edgeColor : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            capStyle: ShapePath.SquareCap
            startX: root.brx; startY: root.by
            PathLine { x: root.blx; y: root.by }
        }
        ShapePath {   // left
            readonly property bool on: root.strokeWidth > 0 && root.strokeLeft && !root.round
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
            strokeColor: root.gauge && !root.round ? root.progressColor : "transparent"
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
            strokeColor: root.gauge && !root.round ? root.progressColor : "transparent"
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

    // ---- lightning ----
    // gaugeSpark (0..1): the gauge itself becomes a live current, with a bright head where it ends.
    // edgeSpark (0..1): a current along the bottom edge (0 = off).
    property real gaugeSpark: 0
    property real edgeSpark: 0
    function sparkBurst(amount) { gR.burst(amount); gL.burst(amount); bottomSpark.burst(amount); }
    readonly property var halfR: gaugeFromTop ? [[midTop, ty], [trx, ty], [brx, by], [midBottom, by]]
                                              : [[midBottom, by], [brx, by], [trx, ty], [midTop, ty]]
    readonly property var halfL: gaugeFromTop ? [[midTop, ty], [tlx, ty], [blx, by], [midBottom, by]]
                                              : [[midBottom, by], [blx, by], [tlx, ty], [midTop, ty]]
    EdgeSpark {
        id: gR
        anchors.fill: parent
        visible: root.gauge && root.gaugeSpark > 0 && !root.round && root.progress > 0.01
        points: root.halfR
        arcTo: Math.max(0.01, root.progress)
        intensity: root.gaugeSpark
        color: root.progressColor
        speed: 1.4
    }
    EdgeSpark {
        id: gL
        anchors.fill: parent
        visible: gR.visible
        points: root.halfL
        arcTo: Math.max(0.01, root.progress)
        intensity: root.gaugeSpark
        color: root.progressColor
        speed: 1.4
    }
    // the two heads: bright flickering points where the current ends
    Repeater {
        model: gR.visible ? [gR, gL] : []
        Rectangle {
            required property var modelData
            readonly property var pt: { root.progress; root.width; return modelData.at(modelData.arcTo); }
            readonly property real sz: 5 + 3 * Math.random() * root.gaugeSpark + flick.v * 2
            x: pt[0] - sz / 2
            y: pt[1] - sz / 2
            width: sz; height: sz; radius: sz / 2
            color: "white"
            antialiasing: true
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 3.2; height: width; radius: width / 2
                color: Qt.rgba(root.progressColor.r, root.progressColor.g, root.progressColor.b, 0.35)
                z: -1
            }
        }
    }
    QtObject {
        id: flick
        property real v: 0
    }
    Timer { interval: 70; repeat: true; running: gR.visible; onTriggered: flick.v = Math.random() }
    EdgeSpark {
        id: bottomSpark
        anchors.fill: parent
        visible: root.edgeSpark > 0
        points: [[root.blx, root.by], [root.brx, root.by]]
        intensity: root.edgeSpark
        speed: 0.8
    }

    Item { id: holder; anchors.fill: parent }
}
