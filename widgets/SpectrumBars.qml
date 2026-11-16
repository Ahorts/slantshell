import QtQuick
import ".."

// Ambient audio spectrum along the bottom edge of the desktop: translucent bars in the palette that
// rise with the music and fade away when it stops. Click-through (sits on the desktop layer).
Item {
    id: root

    readonly property int count: 56
    height: 190
    opacity: Audio.playing ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }

    // 56 bars from the 16 cava bands (bass in the middle, treble toward both edges, so it looks symmetric).
    function level(i) {
        const b = Audio.bars;
        if (!b || b.length === 0) return 0;
        const centre = (count - 1) / 2;
        const f = Math.abs(i - centre) / centre * (b.length - 1);   // 0 at the middle .. 15 at the edges
        const lo = Math.floor(f), hi = Math.min(b.length - 1, lo + 1);
        return ((b[lo] ?? 0) * (1 - (f - lo)) + (b[hi] ?? 0) * (f - lo)) / 100;
    }

    Row {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 8 }
        height: parent.height
        spacing: 4

        Repeater {
            model: root.count

            Rectangle {
                required property int index
                readonly property real lv: root.level(index)
                width: (root.width - 16 - (root.count - 1) * 4) / root.count
                height: Math.max(2, lv * root.height)
                anchors.bottom: parent.bottom
                color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, Math.abs(index - 27.5) / 40))
                opacity: 0.16 + 0.22 * lv
                Behavior on height { NumberAnimation { duration: 80 } }
            }
        }
    }
}
