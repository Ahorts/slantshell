import QtQuick
import QtQuick.Shapes

// Parallelogram panel (skwd-style slanted edges). The top edge is shifted right by `skew`
// relative to the bottom edge, so left and right edges lean like "/".
// Children go in the content area. Set strokeWidth: 0 for a stroke-less shape.
Item {
    id: root

    property real skew: 14
    property color fill: Theme.bg
    property color stroke: Theme.accentContainer
    property real strokeWidth: 1.5

    // Outline gauge: 0..1 draws a bright arc along the outline (clockwise from the top-left),
    // -1 turns it off. Used for countdowns and volume / brightness popups.
    property real progress: -1
    property color progressColor: Theme.accent
    property real progressWidth: 3

    readonly property bool gauge: progress >= 0
    // Approximate outline length (used to size the dash).
    readonly property real perimeter: {
        const pad = strokeWidth / 2;
        const h = height - 2 * pad;
        return (width - pad - skew) + Math.hypot(skew - pad, h) + (width - skew - pad) + Math.hypot(skew - pad, h);
    }

    default property alias content: holder.data

    Behavior on fill { ColorAnimation { duration: 400 } }
    Behavior on stroke { ColorAnimation { duration: 400 } }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            id: path
            readonly property real p: root.strokeWidth / 2   // inset so the stroke isn't clipped

            fillColor: root.fill
            strokeColor: root.strokeWidth > 0
                ? (root.gauge ? Qt.rgba(root.stroke.r, root.stroke.g, root.stroke.b, 0.28) : root.stroke)
                : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            joinStyle: ShapePath.MiterJoin

            startX: root.skew;               startY: path.p
            PathLine { x: root.width - path.p;    y: path.p }
            PathLine { x: root.width - root.skew; y: root.height - path.p }
            PathLine { x: path.p;                 y: root.height - path.p }
            PathLine { x: root.skew;         y: path.p }
        }

        // Gauge arc: the same outline, dashed so only `progress` of it is drawn.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.gauge ? root.progressColor : "transparent"
            strokeWidth: root.progressWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: ShapePath.DashLine
            dashPattern: [Math.max(0.001, root.progress * root.perimeter / root.progressWidth), root.perimeter / root.progressWidth * 2]

            startX: root.skew;               startY: path.p
            PathLine { x: root.width - path.p;    y: path.p }
            PathLine { x: root.width - root.skew; y: root.height - path.p }
            PathLine { x: path.p;                 y: root.height - path.p }
            PathLine { x: root.skew;         y: path.p }
        }
    }

    Item { id: holder; anchors.fill: parent }
}
