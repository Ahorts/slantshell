import Quickshell
import QtQuick
import ".."

// "Pulse clock": a clock inside a ring. The accent arc sweeps once a minute (seconds), and while
// music plays the ring grows audio-reactive bars (live from cava) in the wallpaper palette.
Item {
    id: root

    width: 400
    height: 400

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // Smoothed per-band levels (0..1), 16 bands mirrored around the ring.
    property var levels: new Array(16).fill(0)
    property real peak: 0

    readonly property string greeting: {
        const h = clock.date.getHours();
        if (h < 5) return "Still up?";
        if (h < 12) return "Good morning";
        if (h < 18) return "Good afternoon";
        return "Good evening";
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    // Animate while music plays, and until the bars have settled after it stops.
    Timer {
        interval: 33
        running: Audio.playing || root.peak > 0.01
        repeat: true
        onTriggered: {
            const next = [];
            let p = 0;
            for (let i = 0; i < 16; i++) {
                const target = (Audio.bars[i] ?? 0) / 100;
                const v = root.levels[i] + (target - root.levels[i]) * 0.45;
                next.push(v);
                p = Math.max(p, v);
            }
            root.levels = next;
            root.peak = p;
            canvas.requestPaint();
        }
    }

    Connections { target: clock; function onDateChanged() { canvas.requestPaint(); } }
    Connections { target: Theme; function onAccentChanged() { canvas.requestPaint(); } function onAccent2Changed() { canvas.requestPaint(); } function onAccentContainerChanged() { canvas.requestPaint(); } }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = height / 2, R = 126;
            const c1 = Theme.accent, c2 = Theme.accent2, cc = Theme.accentContainer;

            // Faint base ring.
            ctx.lineWidth = 2;
            ctx.strokeStyle = Qt.rgba(cc.r, cc.g, cc.b, 0.28);
            ctx.beginPath();
            ctx.arc(cx, cy, R, 0, Math.PI * 2);
            ctx.stroke();

            // Seconds sweep.
            const sec = clock.date.getSeconds();
            const a0 = -Math.PI / 2;
            ctx.lineCap = "round";
            ctx.lineWidth = 4;
            ctx.strokeStyle = c1;
            ctx.beginPath();
            ctx.arc(cx, cy, R, a0, a0 + Math.PI * 2 * (sec / 60) + 0.001);
            ctx.stroke();

            // Audio bars around the ring (idle: little dots).
            const n = 32;
            ctx.lineWidth = 5;
            for (let i = 0; i < n; i++) {
                const band = i < 16 ? i : 31 - i;           // mirror: bass at the top on both sides
                const v = root.levels[band];
                const ang = a0 + (i + 0.5) / n * Math.PI * 2;
                const r0 = R + 14;
                const r1 = r0 + 1 + v * 52;
                ctx.strokeStyle = root.mix(c1, c2, i < 16 ? i / 15 : (31 - i) / 15);
                ctx.globalAlpha = 0.35 + 0.65 * Math.min(1, v * 1.6);
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(ang) * r0, cy + Math.sin(ang) * r0);
                ctx.lineTo(cx + Math.cos(ang) * r1, cy + Math.sin(ang) * r1);
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.greeting
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: 17
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 84
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: 15
        }
    }
}
