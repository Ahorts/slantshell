import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "widgets"

// Dashboard face of the island: an instrument cluster of three dials, linked like the switcher's orbit.
//   left   a gauge: three nested arcs (CPU, memory, disk) sweeping round 240 degrees, the CPU figure rolling in
//          the middle, the temperature under it
//   centre the record: the cover art spinning while it plays, inside a ring of audio bars; title, the current lyric
//          line (or the artist), and the transport
//   right  the month as a ring: one dot per day round a circle (past days filled, today glowing, future hollow),
//          the clock and date in the middle; hovering a dot shows that day
// Thin beams with travelling pulses link the side dials to the record.
// Opening: the record pops, the side dials slide out from behind it, the arcs sweep up to their values and the days
// light up round the ring one after another. Everything springs; nothing covers it while it opens.
Item {
    id: face

    property bool active: false
    signal closeRequested()

    readonly property real faceW: 1060
    readonly property real faceH: 440

    readonly property real dialY: 212
    readonly property real sideR: 142
    readonly property real midX: faceW / 2
    readonly property real leftX: 190
    readonly property real rightX: faceW - 190

    // ---- choreography ----
    property real pop: active ? 1 : 0                       // the record
    Behavior on pop { SpringAnimation { spring: 4.0; damping: 0.42; epsilon: 0.002 } }
    property real wings: active ? 1 : 0                     // side dials slide out
    Behavior on wings {
        SequentialAnimation {
            PauseAnimation { duration: face.active ? 110 : 0 }
            SpringAnimation { spring: 3.4; damping: 0.46; epsilon: 0.002 }
        }
    }
    property real sweep: 0                                  // arcs and day dots fill in
    NumberAnimation { id: sweepIn; target: face; property: "sweep"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
    onActiveChanged: if (active) { sweep = 0; sweepIn.restart(); statFile.reload(); memFile.reload(); upFile.reload(); tempFile.reload(); }

    // ---- data ----
    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var now: clock.date

    readonly property var player: Audio.player ?? (Mpris.players.values.find(p => (p.trackTitle ?? "") !== "") ?? null)
    readonly property bool isPlaying: player !== null && player.isPlaying

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property real cpuTemp: 0
    property string uptime: ""
    property var _prevStat: null
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isPresent && battery.isLaptopBattery

    function parseStat(t) {
        const f = t.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idleT = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
        if (_prevStat) {
            const dt = total - _prevStat.total, di = idleT - _prevStat.idle;
            if (dt > 0) cpu = Math.max(0, Math.min(1, 1 - di / dt));
        }
        _prevStat = { total: total, idle: idleT };
    }
    function parseMem(t) {
        const get = k => Number((t.match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
        const total = get("MemTotal"), avail = get("MemAvailable");
        if (total > 0) mem = 1 - avail / total;
    }
    function parseUptime(t) {
        const s = Math.floor(Number(t.split(" ")[0]));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        uptime = (d > 0 ? d + "d " : "") + h + "h " + m + "m";
    }
    FileView { id: statFile; path: "/proc/stat"; onLoaded: face.parseStat(text()) }
    FileView { id: memFile; path: "/proc/meminfo"; onLoaded: face.parseMem(text()) }
    FileView { id: upFile; path: "/proc/uptime"; onLoaded: face.parseUptime(text()) }
    FileView {
        id: tempFile
        path: "/sys/class/thermal/thermal_zone2/temp"
        onLoaded: { const v = Number(text().trim()); if (!isNaN(v) && v > 0) face.cpuTemp = Math.round(v / 1000); }
    }
    Process {
        id: dfProc
        command: ["df", "--output=pcent", "/"]
        stdout: StdioCollector { onStreamFinished: { const m = text.match(/(\d+)%/); if (m) face.disk = Number(m[1]) / 100; } }
    }
    Timer {
        interval: 1500; running: face.active; repeat: true; triggeredOnStart: true
        onTriggered: { statFile.reload(); memFile.reload(); upFile.reload(); tempFile.reload(); }
    }
    Timer { interval: 30000; running: face.active; repeat: true; triggeredOnStart: true; onTriggered: dfProc.running = true }

    Rectangle {
        id: backdropMask
        anchors.fill: parent
        anchors.margins: 1
        topLeftRadius: 0; topRightRadius: 0; bottomLeftRadius: 27; bottomRightRadius: 27
        antialiasing: true
        visible: false
        layer.enabled: true
    }
    // ---- backdrop: the cover art, blurred, as ambient light; soft glows drifting behind the dials; a faint dot grid
    Item {
        id: backdrop
        anchors.fill: parent
        z: -1
        opacity: Math.min(1, face.pop)
        // clipped to the island's dashboard shape (square top, rounded bottom corners, radius 28 as in Island.qml),
        // so the blurred art and glows don't show as a square shadow outside the rounded corners
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: backdropMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        Image {
            id: bgArt
            anchors.fill: parent
            source: face.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: bgArt
            visible: bgArt.status === Image.Ready
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
            opacity: 0.32
        }
        // glows: one behind each dial, drifting slowly (only while the dashboard is open)
        Repeater {
            model: [
                { x: face.leftX, c: Theme.accent2 },
                { x: face.midX, c: Theme.accent },
                { x: face.rightX, c: Theme.accentContainer }
            ]
            Rectangle {
                id: glow
                required property var modelData
                required property int index
                property real drift: 0
                SequentialAnimation on drift {
                    running: face.active; loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 5200 + glow.index * 1300; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0; duration: 5200 + glow.index * 1300; easing.type: Easing.InOutSine }
                }
                width: 420; height: 420; radius: 210
                x: modelData.x - 210 + (drift - 0.5) * 60
                y: face.dialY - 210 + (0.5 - drift) * 30
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(glow.modelData.c.r, glow.modelData.c.g, glow.modelData.c.b, 0.22) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
            }
        }
        // faint dot grid, fading towards the edges (painted once)
        Canvas {
            id: dotGrid
            anchors.fill: parent
            opacity: 0.5
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                for (let x = 12; x < width; x += 22)
                    for (let y = 12; y < height; y += 22) {
                        const dx = (x - width / 2) / (width / 2), dy = (y - height / 2) / (height / 2);
                        const a = Math.max(0, 0.22 * (1 - Math.min(1, Math.hypot(dx * 0.9, dy * 1.1))));
                        if (a <= 0.01) continue;
                        ctx.fillStyle = Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, a);
                        ctx.fillRect(x, y, 1.6, 1.6);
                    }
            }
            Connections { target: Theme; function onFgChanged() { dotGrid.requestPaint(); } }
        }
    }

    // ---- beams between the dials (with a pulse running along each) ----
    component Beam: Item {
        id: bm
        property real x1: 0
        property real x2: 0
        property real y0: face.dialY
        property bool reverse: false
        anchors.fill: parent
        opacity: Math.min(1, face.wings)
        Rectangle {
            x: Math.min(bm.x1, bm.x2); y: bm.y0
            width: Math.abs(bm.x2 - bm.x1) * Math.min(1, face.wings); height: 1
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.14)
        }
        Rectangle {
            property real t: 0
            NumberAnimation on t { from: 0; to: 1; duration: 1600; loops: Animation.Infinite; running: face.active }
            readonly property real px: bm.reverse ? bm.x2 + (bm.x1 - bm.x2) * t : bm.x1 + (bm.x2 - bm.x1) * t
            x: px - 3; y: bm.y0 - 3
            width: 7; height: 7; radius: 3.5
            color: Theme.accent
            opacity: Math.sin(Math.PI * t) * 0.9
            Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; z: -1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) }
        }
    }
    Beam { x1: face.leftX + face.sideR * face.wings + 4; x2: face.midX - 150; reverse: true }
    Beam { x1: face.midX + 150; x2: face.rightX - face.sideR * face.wings - 4 }

    // ---- an arc meter: track + value, 240 degrees, starting bottom-left ----
    component Meter: Shape {
        id: mt
        property real r: 100
        property real value: 0
        property color col: Theme.accent
        property real thick: 9
        property real shown: value * face.sweep
        Behavior on shown { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(mt.col.r, mt.col.g, mt.col.b, 0.14)
            strokeWidth: mt.thick
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: mt.width / 2; centerY: mt.height / 2; radiusX: mt.r; radiusY: mt.r; startAngle: 150; sweepAngle: 240 }
        }
        ShapePath {
            strokeColor: mt.col
            strokeWidth: mt.thick
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: mt.width / 2; centerY: mt.height / 2; radiusX: mt.r; radiusY: mt.r; startAngle: 150; sweepAngle: Math.max(0.5, 240 * Math.min(1, mt.shown)) }
        }
    }

    // a dial's disc
    component Disc: Rectangle {
        property real r: face.sideR
        width: r * 2; height: r * 2; radius: r
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        antialiasing: true
    }

    // =================================================================== LEFT: the gauge
    Item {
        id: gauge
        width: face.sideR * 2; height: face.sideR * 2
        x: face.midX + (face.leftX - face.midX) * face.wings - width / 2
        y: face.dialY - height / 2
        opacity: Math.min(1, face.wings * 1.4)
        scale: 0.7 + 0.3 * Math.min(1, face.wings)
        Disc { anchors.centerIn: parent }
        Meter { r: 122; value: face.cpu; col: Theme.accent }
        Meter { r: 104; value: face.mem; col: Theme.accent2; thick: 7 }
        Meter { r: 89; value: face.disk; col: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75); thick: 5 }
        // scale ticks round the outside
        Repeater {
            model: 13
            Rectangle {
                required property int index
                readonly property real a: (150 + index * 20) * Math.PI / 180
                x: gauge.width / 2 + Math.cos(a) * 136 - 1
                y: gauge.height / 2 + Math.sin(a) * 136 - 1
                width: 2; height: 2; radius: 1
                color: index % 3 === 0 ? Theme.fg : Theme.fgDim
                opacity: index / 12 <= face.sweep ? 0.8 : 0
            }
        }
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            spacing: 0
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                RollText { text: String(Math.round(face.cpu * 100 * face.sweep)); color: Theme.fg; font: Qt.font({ family: Theme.font, pixelSize: 40, bold: true }) }
                Text { text: "%"; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 7 }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "cpu"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 11; font.bold: true; font.letterSpacing: 2 }
        }
        // legend + temperature, in the gap at the bottom of the arcs
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 52
            spacing: 10
            Repeater {
                model: [
                    { c: Theme.accent2, t: "mem " + Math.round(face.mem * 100) + "%" },
                    { c: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75), t: "disk " + Math.round(face.disk * 100) + "%" }
                ]
                Row {
                    required property var modelData
                    spacing: 4
                    Rectangle { width: 6; height: 6; radius: 3; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: modelData.t; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 30
            width: tempT.implicitWidth + 18; height: 20; radius: 10
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            Text { id: tempT; anchors.centerIn: parent; text: "󰔏 " + face.cpuTemp + "°C"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 10; font.bold: true }
        }
    }

    // =================================================================== CENTRE: the record
    Item {
        id: rec
        readonly property real rr: 150
        width: rr * 2; height: rr * 2
        x: face.midX - rr
        y: face.dialY - rr - 22
        scale: Math.max(0.01, face.pop)
        opacity: Math.min(1, face.pop * 1.5)
        z: 2

        // audio bars round the record (32, from the cava feed), reaching outward
        Repeater {
            model: 40
            Rectangle {
                required property int index
                readonly property real lvl: face.isPlaying ? (Audio.bars[index % Math.max(1, Audio.bars.length)] ?? 0) / 100 : 0.05
                readonly property real a: index / 40 * 360
                x: rec.rr - 1.5
                y: rec.rr - 120 - h
                property real h: 4 + 26 * lvl
                width: 3; height: h; radius: 1.5
                color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 40))
                opacity: 0.85
                transform: Rotation { origin.x: 1.5; origin.y: 120 + h; angle: a }
                Behavior on h { NumberAnimation { duration: 70 } }
            }
        }
        // the disc
        Rectangle {
            id: vinyl
            anchors.centerIn: parent
            width: 226; height: 226; radius: 113
            color: "#0c0c10"
            border.color: Qt.rgba(1, 1, 1, 0.08)
            antialiasing: true
            property real spin: 0
            FrameAnimation { running: face.active && face.isPlaying; onTriggered: vinyl.spin = (vinyl.spin + frameTime * 30) % 360 }
            rotation: vinyl.spin
            // grooves
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: 210 - index * 20; height: width; radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                }
            }
            // cover art, round
            Item {
                anchors.centerIn: parent
                width: 120; height: 120
                layer.enabled: true
                layer.effect: MultiEffect { maskEnabled: true; maskSource: artMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                Image {
                    id: art
                    anchors.fill: parent
                    source: face.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Rectangle { anchors.fill: parent; visible: art.status !== Image.Ready; color: Theme.accentContainer
                    Text { anchors.centerIn: parent; text: "󰎈"; color: Theme.accent; font.family: Theme.font; font.pixelSize: 40 } }
            }
            Rectangle { id: artMask; anchors.centerIn: parent; width: 120; height: 120; radius: 60; visible: false; layer.enabled: true }
            Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: "#0c0c10"; border.color: Theme.accent; border.width: 2 }
        }
        // a quiet current round the record, pulsing with the bass
        EdgeSpark {
            anchors.fill: parent
            visible: Theme.lightning && face.active
            ring: true
            cx: rec.rr; cy: rec.rr
            r: 117
            intensity: face.isPlaying ? 0.08 + 0.2 * Math.min(1, (Audio.bars[1] ?? 0) / 100) : 0.05
            speed: face.isPlaying ? 1.3 : 0.5
        }
    }
    // title, lyric/artist, transport
    Column {
        anchors.horizontalCenter: rec.horizontalCenter
        y: rec.y + rec.height - 4
        spacing: 3
        opacity: Math.min(1, face.pop * 1.4)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, 380)
            text: face.player ? (face.player.trackTitle || "Unknown track") : "Nothing playing"
            color: Theme.fg; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font; font.pixelSize: 16; font.bold: true
        }
        Text {
            id: subLine
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, 420)
            readonly property bool lyric: Lyrics.hasLyrics && Lyrics.line !== ""
            text: lyric ? Lyrics.line : (face.player?.trackArtist ?? "")
            color: lyric ? Theme.accent : Theme.fgDim
            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font; font.pixelSize: 12; font.italic: lyric
            onTextChanged: subIn.restart()
            transform: Translate { id: subShift }
            ParallelAnimation {
                id: subIn
                NumberAnimation { target: subShift; property: "y"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                NumberAnimation { target: subLine; property: "opacity"; from: 0; to: 1; duration: 240 }
            }
        }
    }
    Row {
        anchors.horizontalCenter: rec.horizontalCenter
        y: face.faceH - 52
        spacing: 12
        opacity: Math.min(1, face.pop * 1.4)
        Repeater {
            model: [{ act: "prev", icon: "󰒮" }, { act: "play", icon: "" }, { act: "next", icon: "󰒭" }]
            Rectangle {
                id: tb
                required property var modelData
                readonly property bool main: modelData.act === "play"
                width: main ? 64 : 42; height: 38; radius: 19
                color: main ? Theme.accent : (tbm.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
                scale: tbm.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: tb.main ? (face.isPlaying ? "󰏤" : "󰐊") : tb.modelData.icon
                    color: tb.main ? Theme.accentText : Theme.fg
                    font.family: Theme.font; font.pixelSize: 17
                }
                MouseArea {
                    id: tbm
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const p = face.player; if (!p) return;
                        if (tb.modelData.act === "prev") p.previous(); else if (tb.modelData.act === "next") p.next(); else p.togglePlaying();
                    }
                }
            }
        }
    }

    // =================================================================== RIGHT: the month ring
    Item {
        id: month
        width: face.sideR * 2; height: face.sideR * 2
        x: face.midX + (face.rightX - face.midX) * face.wings - width / 2
        y: face.dialY - height / 2
        opacity: Math.min(1, face.wings * 1.4)
        scale: 0.7 + 0.3 * Math.min(1, face.wings)
        readonly property int days: new Date(face.now.getFullYear(), face.now.getMonth() + 1, 0).getDate()
        readonly property int today: face.now.getDate()
        property int hovered: -1
        Disc { anchors.centerIn: parent }
        // day progress arc (how far through today)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: month.width / 2; centerY: month.height / 2; radiusX: 98; radiusY: 98; startAngle: -90
                    sweepAngle: Math.max(0.5, 360 * face.sweep * (face.now.getHours() * 3600 + face.now.getMinutes() * 60 + face.now.getSeconds()) / 86400)
                }
            }
        }
        Repeater {
            model: month.days
            Item {
                id: day
                required property int index
                readonly property int n: index + 1
                readonly property real a: (index / month.days * 360 - 90) * Math.PI / 180
                readonly property bool isToday: n === month.today
                readonly property bool past: n < month.today
                readonly property real lit: Math.max(0, Math.min(1, face.sweep * month.days * 1.15 - index))
                readonly property real s: isToday ? 14 : (month.hovered === index ? 11 : 7)
                x: month.width / 2 + Math.cos(a) * 120 - 12
                y: month.height / 2 + Math.sin(a) * 120 - 12
                width: 24; height: 24
                Rectangle {
                    anchors.centerIn: parent
                    width: day.s; height: day.s; radius: day.s / 2
                    Behavior on width { SpringAnimation { spring: 5; damping: 0.45 } }
                    Behavior on height { SpringAnimation { spring: 5; damping: 0.45 } }
                    color: day.isToday ? Theme.accent : (day.past ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : "transparent")
                    border.color: day.isToday ? Theme.accent : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35)
                    border.width: day.past || day.isToday ? 0 : 1
                    scale: day.lit
                    antialiasing: true
                }
                // today breathes
                Rectangle {
                    visible: day.isToday
                    anchors.centerIn: parent
                    width: 26; height: 26; radius: 13
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: 1.5
                    SequentialAnimation on scale {
                        running: face.active && day.isToday; loops: Animation.Infinite
                        NumberAnimation { from: 0.7; to: 1.25; duration: 1100; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.25; to: 0.7; duration: 1100; easing.type: Easing.InCubic }
                    }
                    opacity: 0.7 * day.lit
                }
                MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: month.hovered = day.index; onExited: if (month.hovered === day.index) month.hovered = -1 }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 0
            RollText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(face.now, "HH:mm")
                color: Theme.fg
                font: Qt.font({ family: Theme.font, pixelSize: 38, bold: true })
            }
            Text {
                id: dateLine
                anchors.horizontalCenter: parent.horizontalCenter
                text: month.hovered >= 0
                      ? Qt.formatDate(new Date(face.now.getFullYear(), face.now.getMonth(), month.hovered + 1), "dddd d")
                      : Qt.formatDate(face.now, "dddd d MMMM")
                color: month.hovered >= 0 ? Theme.accent : Theme.fgDim
                font.family: Theme.font; font.pixelSize: 11
            }
            Item { width: 1; height: 6 }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: upT.implicitWidth + 16; height: 18; radius: 9
                color: Qt.rgba(1, 1, 1, 0.06)
                Text { id: upT; anchors.centerIn: parent; text: (face.hasBattery ? "󰁹 " + Math.round(face.battery.percentage * 100) + "%  ·  " : "") + "up " + face.uptime; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 9 }
            }
        }
    }
}
