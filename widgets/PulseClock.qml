import Quickshell
import QtQuick
import QtQuick.Shapes
import ".."

// "Pulse clock": a clock inside a ring. The accent arc sweeps once a minute (seconds), and while
// music plays the ring grows audio-reactive bars (live from cava) in the wallpaper palette.
// Drawn with vector shapes and plain items (no per-frame canvas painting), so it stays cheap.
Item {
    id: root

    width: 400
    height: 400

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // Smoothed per-band levels (0..1), 16 bands mirrored around the ring.
    property var levels: new Array(16).fill(0)
    property real peak: 0

    readonly property real ringR: 126
    readonly property int barCount: 32

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
        interval: 50                       // 20 fps is plenty for a background ring
        running: (Audio.playing || root.peak > 0.01) && root.visible
        repeat: true
        onTriggered: {
            const next = [];
            let p = 0;
            for (let i = 0; i < 16; i++) {
                const target = (Audio.bars[i] ?? 0) / 100;
                const v = root.levels[i] + (target - root.levels[i]) * 0.5;
                next.push(v);
                p = Math.max(p, v);
            }
            root.levels = next;
            root.peak = p;
        }
    }

    // ---- the ring and the seconds sweep ----
    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.28)
            strokeWidth: 2
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.ringR; radiusY: root.ringR; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.accent
            strokeWidth: 4
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.ringR; radiusY: root.ringR
                startAngle: -90
                sweepAngle: Math.max(0.5, clock.date.getSeconds() * 6)
            }
        }
    }

    // ---- audio bars around the ring (idle: little dots) ----
    Repeater {
        model: root.barCount

        Item {
            id: slot
            required property int index
            // mirror the 16 bands so bass sits at the top on both sides
            readonly property int band: index < 16 ? index : 31 - index
            readonly property real lv: root.levels[band] ?? 0
            x: root.width / 2
            y: root.height / 2
            rotation: -90 + (index + 0.5) / root.barCount * 360

            Rectangle {
                x: root.ringR + 14
                y: -2.5
                width: 1 + slot.lv * 52
                height: 5
                color: root.mix(Theme.accent, Theme.accent2, slot.band / 15)
                opacity: 0.35 + 0.65 * Math.min(1, slot.lv * 1.6)
            }
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
