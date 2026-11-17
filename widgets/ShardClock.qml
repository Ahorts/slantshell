import Quickshell
import QtQuick
import QtQuick.Shapes
import ".."

// "Shard clock" for the desktop, in the bar's slanted language (the dashboard and lock screen already use rings):
// big slanted digits that roll when they change (hours in the foreground colour, minutes in the accent), a thin
// seconds line underneath that steps forward once a second with a glowing head, the greeting and date, and a
// slanted glass shard behind it all. While music plays a small equaliser grows out of the shard's top edge.
// Idle cost: one short repaint a second (the seconds step); the equaliser runs only while music plays.
Item {
    id: root
    width: 440
    height: 238          // shard (y 30..234) + 4: the weather shard below continues its edges (see WeatherShard)

    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var now: clock.date
    readonly property string greeting: {
        const h = now.getHours();
        if (h < 5) return "still up?";
        if (h < 12) return "good morning";
        if (h < 18) return "good afternoon";
        return "good evening";
    }
    readonly property int dayOfYear: Math.floor((now - new Date(now.getFullYear(), 0, 0)) / 86400000)

    // ---- the shard behind ----
    readonly property real slant: 34
    Shape {
        id: shard
        x: 6; y: 30
        width: 400; height: 204
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: shard.width; y2: shard.height
                GradientStop { position: 0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55) }
                GradientStop { position: 1; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.15) }
            }
            strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            strokeWidth: 1
            startX: root.slant; startY: 0
            PathLine { x: shard.width; y: 0 }
            PathLine { x: shard.width - root.slant; y: shard.height }
            PathLine { x: 0; y: shard.height }
            PathLine { x: root.slant; y: 0 }
        }
    }
    // accent notch on the shard's leading edge
    Rectangle {
        x: shard.x + root.slant - 2; y: shard.y
        width: 3; height: 46
        color: Theme.accent
        antialiasing: true
        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -root.slant / shard.height, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
    }

    // ---- equaliser out of the shard's top edge (music only) ----
    property var levels: new Array(24).fill(0)
    property real peak: 0
    Timer {
        interval: 50
        running: (Audio.playing || root.peak > 0.01) && root.visible
        repeat: true
        onTriggered: {
            const src = Audio.bars, out = root.levels.slice();
            let pk = 0;
            for (let i = 0; i < out.length; i++) {
                const v = Audio.playing && src.length ? (src[Math.floor(i * src.length / out.length)] ?? 0) / 100 : 0;
                out[i] = v > out[i] ? v : out[i] * 0.82;
                pk = Math.max(pk, out[i]);
            }
            root.levels = out;
            root.peak = pk;
        }
    }
    Row {
        x: shard.x + root.slant + 60
        y: shard.y - 1
        spacing: 4
        opacity: Math.min(1, root.peak * 3)
        visible: root.peak > 0.01
        Repeater {
            model: 24
            Rectangle {
                required property int index
                readonly property real h: 2 + 34 * root.levels[index]
                width: 6; height: h
                y: -h
                color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 24))
                opacity: 0.85
                antialiasing: true
                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.35, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
            }
        }
    }

    // ---- the time ----
    Row {
        id: timeRow
        x: shard.x + root.slant + 22
        y: shard.y + 6
        spacing: 2
        RollText {
            spacing: -6
            text: Qt.formatDateTime(root.now, "HH")
            color: Theme.fg
            font: Qt.font({ family: Theme.font, pixelSize: 96, bold: true, italic: true })
        }
        // the separator: a short slanted bar, not a colon
        Rectangle {
            width: 6; height: 54
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 6
            color: Theme.accent
            opacity: 0.8
            antialiasing: true
            transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.25, 0, 7, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
        }
        Item { width: 6; height: 1 }
        RollText {
            spacing: -6
            text: Qt.formatDateTime(root.now, "mm")
            color: Theme.accent
            font: Qt.font({ family: Theme.font, pixelSize: 96, bold: true, italic: true })
        }
    }

    // ---- seconds line: steps forward once a second, a glowing head at the tip ----
    Item {
        id: secs
        x: shard.x + root.slant + 10
        y: shard.y + 124
        width: 290; height: 4
        Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.1) }
        Rectangle {
            id: fill
            height: parent.height; radius: 2
            color: Theme.accent
            property real frac: root.now.getSeconds() / 59
            width: Math.max(4, parent.width * frac)
            Behavior on width { enabled: fill.frac > 0.01; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: fill.width - 6; y: -4
            width: 12; height: 12; radius: 6
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: "white" }
        }
        Text {
            anchors { left: parent.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text: Qt.formatDateTime(root.now, "ss")
            color: Theme.fgDim
            font.family: Theme.font; font.pixelSize: 11; font.bold: true
        }
    }

    // ---- greeting and date ----
    Column {
        x: shard.x + root.slant + 6
        y: shard.y + 142
        spacing: 1
        Text {
            text: root.greeting
            color: Theme.accent
            font.family: Theme.font; font.pixelSize: 12; font.bold: true; font.letterSpacing: 2; font.capitalization: Font.AllUppercase
        }
        Text {
            text: Qt.formatDateTime(root.now, "dddd · d MMMM") + "   ·   day " + root.dayOfYear
            color: Theme.fgDim
            font.family: Theme.font; font.pixelSize: 12
        }
    }
}
