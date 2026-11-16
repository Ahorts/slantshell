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
            strokeColor: root.strokeWidth > 0 ? root.stroke : "transparent"
            strokeWidth: root.strokeWidth > 0 ? root.strokeWidth : -1
            joinStyle: ShapePath.MiterJoin

            startX: root.skew;               startY: path.p
            PathLine { x: root.width - path.p;    y: path.p }
            PathLine { x: root.width - root.skew; y: root.height - path.p }
            PathLine { x: path.p;                 y: root.height - path.p }
            PathLine { x: root.skew;         y: path.p }
        }
    }

    Item { id: holder; anchors.fill: parent }
}
