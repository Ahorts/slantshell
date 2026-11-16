import QtQuick
import ".."

// Liquid-fill gauge: a round glass with two layers of water that rise to `value` (0..1) and keep
// rippling. The waves only animate while the orb is visible, so it costs nothing when hidden.
Item {
    id: orb

    property real value: 0
    property color color: Theme.accent
    property string label: ""
    property string valueText: Math.round(value * 100) + "%"

    implicitWidth: 80
    implicitHeight: 100

    // Level eases toward `value`; phase drives the waves.
    property real shown: value
    Behavior on shown { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
    property real phase: 0

    FrameAnimation {
        running: orb.visible && orb.opacity > 0
        onTriggered: {
            orb.phase += frameTime * 2.4;
            canvas.requestPaint();
        }
    }
    onColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        width: 72
        height: 72
        anchors.horizontalCenter: parent.horizontalCenter
        antialiasing: true

        function wave(ctx, cx, cy, r, levelY, amp, k, ph, alpha) {
            ctx.beginPath();
            ctx.moveTo(cx - r, cy + r);
            for (let x = cx - r; x <= cx + r; x += 2)
                ctx.lineTo(x, levelY + amp * Math.sin((x - cx) / r * k * Math.PI + ph));
            ctx.lineTo(cx + r, cy + r);
            ctx.closePath();
            ctx.globalAlpha = alpha;
            ctx.fillStyle = orb.color;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, r = 33;
            const v = Math.max(0, Math.min(1, orb.shown));
            const levelY = cy + r - 2 * r * v;
            // Waves flatten out when the glass is empty or full.
            const calm = Math.sin(Math.min(1, Math.max(0.0, v)) * Math.PI);
            const amp = 1.2 + 3.4 * calm;

            // Glass body
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7);
            ctx.fill();

            // Water, clipped to the glass
            ctx.save();
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.clip();
            if (v > 0.003) {
                wave(ctx, cx, cy, r, levelY, amp * 0.9, 2.1, orb.phase * 0.8 + 1.7, 0.45);
                wave(ctx, cx, cy, r, levelY + 1.5, amp, 3.0, orb.phase, 0.92);
            }
            ctx.restore();

            // Rim and a small highlight
            ctx.lineWidth = 2;
            ctx.strokeStyle = Qt.rgba(orb.color.r, orb.color.g, orb.color.b, 0.85);
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            ctx.lineWidth = 3;
            ctx.lineCap = "round";
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.22);
            ctx.beginPath();
            ctx.arc(cx, cy, r - 7, Math.PI * 1.08, Math.PI * 1.38);
            ctx.stroke();
        }
    }

    Text {
        anchors.centerIn: canvas
        text: orb.valueText
        color: Theme.fg
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.45)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: orb.label
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
}
