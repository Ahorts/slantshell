import QtQuick
import ".."

// Circular gauge: value 0..1 with a centred percentage and a label underneath.
Item {
    id: ring

    property real value: 0
    property color color: Theme.accent
    property string label: ""
    property string valueText: Math.round(value * 100) + "%"

    implicitWidth: 64
    implicitHeight: 84

    // Smoothly animated copy of `value`.
    property real shown: value
    Behavior on shown { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    onShownChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        width: 64
        height: 64
        anchors.horizontalCenter: parent.horizontalCenter
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, r = 26;
            ctx.lineWidth = 6;
            ctx.lineCap = "round";

            ctx.strokeStyle = Theme.surface;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            const v = Math.max(0, Math.min(1, ring.shown));
            if (v > 0.005) {
                ctx.strokeStyle = ring.color;
                ctx.beginPath();
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * v);
                ctx.stroke();
            }
        }

        Connections {
            target: Theme
            function onSurfaceChanged() { canvas.requestPaint(); }
        }
    }

    Text {
        anchors.centerIn: canvas
        text: ring.valueText
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: ring.label
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
