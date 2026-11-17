import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import "widgets"

// Dashboard face of the island (sculpted Pocket-Dots + Anserin style — no nested boxy parallelogram cages,
// no 42 small squares on the calendar, no twisted sliver tags):
//   - Centre hub: mechanical vinyl turntable with circular-masked cover art, swinging tonearm,
//     32 radial audio-reactive spectrum bars, counter-rotating tick ring, click-to-flip synced lyrics,
//     and pill transport controls.
//   - Left wing (unfolds on a spring): live chrono header + clean borderless month calendar
//     (only Today and the hovered day get a pill highlight; wheel or arrows browse months).
//   - Right wing (unfolds on a spring): dual auto-scaling live telemetry sparklines (CPU & RAM
//     history with hover crosshair + CPU package temperature + uptime) above four rippling LiquidOrb gauges.
Item {
    id: face

    property bool active: false
    signal closeRequested()

    readonly property real faceW: 1000
    readonly property real faceH: 454
    readonly property real cx: faceW / 2
    readonly property real cy: 184

    // ---- Staggered spring choreography ----
    property real hubGrow: active ? 1 : 0
    Behavior on hubGrow { SpringAnimation { spring: 4.0; damping: 0.44; epsilon: 0.002 } }

    property real wingL: active ? 1 : 0
    Behavior on wingL {
        SequentialAnimation {
            PauseAnimation { duration: face.active ? 70 : 0 }
            SpringAnimation { spring: 3.6; damping: 0.44; epsilon: 0.002 }
        }
    }

    property real wingR: active ? 1 : 0
    Behavior on wingR {
        SequentialAnimation {
            PauseAnimation { duration: face.active ? 130 : 0 }
            SpringAnimation { spring: 3.6; damping: 0.44; epsilon: 0.002 }
        }
    }

    // ---- Continuous animation clock (vinyl spin, ticks) ----
    property real idle: 0
    property real spinDeg: 0
    FrameAnimation {
        running: face.active && face.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            face.idle += dt;
            if (face.isPlaying) face.spinDeg = (face.spinDeg + dt * 42) % 360;
        }
    }

    // ---- Clock & Calendar state ----
    SystemClock { id: clock; precision: SystemClock.Seconds }
    readonly property var now: clock.date

    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()
    readonly property bool isCurrentMonth: viewYear === now.getFullYear() && viewMonth === now.getMonth()

    function goToToday() {
        viewYear = now.getFullYear();
        viewMonth = now.getMonth();
    }
    function stepMonth(delta) {
        let m = viewMonth + delta;
        let y = viewYear;
        if (m < 0) { m = 11; y--; }
        else if (m > 11) { m = 0; y++; }
        viewMonth = m;
        viewYear = y;
    }

    onActiveChanged: if (active) {
        goToToday();
        statFile.reload(); memFile.reload(); upFile.reload(); tempFile.reload();
    }

    // DST-safe 42-cell calendar grid (Monday first)
    readonly property var gridCells: {
        const y = face.viewYear;
        const m = face.viewMonth;
        const todayY = face.now.getFullYear();
        const todayM = face.now.getMonth();
        const todayD = face.now.getDate();
        const firstDow = (new Date(y, m, 1, 12).getDay() + 6) % 7;
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(y, m, 1 - firstDow + i, 12);
            const cy = d.getFullYear(), cm = d.getMonth(), cd = d.getDate();
            cells.push({
                day: cd,
                inMonth: cm === m,
                isToday: cy === todayY && cm === todayM && cd === todayD,
                isWeekend: (i % 7) >= 5
            });
        }
        return cells;
    }

    // ---- Media state ----
    readonly property var player: Audio.player ?? (Mpris.players.values.find(p => (p.trackTitle ?? "") !== "") ?? null)
    readonly property bool isPlaying: player !== null && player.isPlaying
    property bool showLyrics: false

    // ---- Live System Telemetry (CPU, RAM, Temp, Disk, Battery, Uptime) ----
    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property real cpuTemp: 0
    property string uptime: ""
    property var _prevStat: null
    property var cpuHist: []
    property var memHist: []
    property int hoverSample: -1

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isPresent && battery.isLaptopBattery

    readonly property var ceilSteps: [5, 10, 15, 20, 30, 40, 50, 75, 100]
    function ceilFor(arr) {
        let m = 0;
        for (let i = 0; i < arr.length; i++) if (arr[i] > m) m = arr[i];
        m *= 1.22;
        for (let i = 0; i < ceilSteps.length; i++) if (m <= ceilSteps[i]) return ceilSteps[i];
        return 100;
    }
    readonly property int cpuCeil: ceilFor(cpuHist)
    readonly property int memCeil: ceilFor(memHist)

    function pushSample(arr, v) {
        const next = arr.slice(-47);
        next.push(v);
        return next;
    }

    function parseStat(t) {
        const f = t.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idleT = f[3] + (f[4] || 0);
        const total = f.reduce((a, b) => a + b, 0);
        if (_prevStat) {
            const dt = total - _prevStat.total, di = idleT - _prevStat.idle;
            if (dt > 0) {
                cpu = Math.max(0, Math.min(1, 1 - di / dt));
                cpuHist = pushSample(cpuHist, Math.round(cpu * 1000) / 10);
            }
        }
        _prevStat = { total: total, idle: idleT };
    }

    function parseMem(t) {
        const get = k => Number((t.match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
        const total = get("MemTotal"), avail = get("MemAvailable");
        if (total > 0) {
            mem = 1 - avail / total;
            memHist = pushSample(memHist, Math.round(mem * 1000) / 10);
        }
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
        onLoaded: {
            const v = Number(text().trim());
            if (!isNaN(v) && v > 0) face.cpuTemp = Math.round(v / 1000);
        }
    }

    Process {
        id: dfProc
        command: ["df", "--output=pcent", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)%/);
                if (m) face.disk = Number(m[1]) / 100;
            }
        }
    }

    Timer {
        interval: 1500
        running: face.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            upFile.reload();
            tempFile.reload();
            graphCanvas.requestPaint();
        }
    }
    Timer {
        interval: 30000
        running: face.active
        repeat: true
        triggeredOnStart: true
        onTriggered: dfProc.running = true
    }

    // Subtle vertical hairlines separating the 3 stages (Pocket-Dots style)
    Rectangle {
        x: 332; y: 34
        width: 1; height: face.faceH - 68
        color: Qt.rgba(1, 1, 1, 0.07)
        opacity: face.wingL
    }
    Rectangle {
        x: face.faceW - 333; y: 34
        width: 1; height: face.faceH - 68
        color: Qt.rgba(1, 1, 1, 0.07)
        opacity: face.wingR
    }

    // =========================================================================
    // LEFT WING: CLEAN BORDERLESS CHRONO-CALENDAR (No small squares!)
    // =========================================================================
    Item {
        id: leftWing
        x: 22 + (1 - face.wingL) * 110
        y: 18
        width: 294
        height: face.faceH - 36
        opacity: Math.min(1, face.wingL * 1.4)
        scale: 0.90 + 0.10 * face.wingL

        WheelHandler {
            onWheel: event => face.stepMonth(event.angleDelta.y > 0 ? -1 : 1)
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // ---- Live Chrono Header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: -2
                    RowLayout {
                        spacing: 6
                        Text {
                            text: Qt.formatDateTime(face.now, "HH:mm")
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 34
                            font.bold: true
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 32; height: 20
                            radius: 10
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            Text {
                                anchors.centerIn: parent
                                text: Qt.formatDateTime(face.now, "ss")
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }
                    Text {
                        text: Qt.formatDateTime(face.now, "dddd · d MMMM yyyy")
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                Item { Layout.fillWidth: true }

                // Jump to Today pill when browsing other months
                Rectangle {
                    visible: !face.isCurrentMonth
                    width: 56; height: 24
                    radius: 12
                    color: todayHover.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: "Today"
                        color: todayHover.containsMouse ? Theme.accentText : Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: todayHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: face.goToToday()
                    }
                }
            }

            // Live 60-second smooth sweep bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.08)
                Rectangle {
                    width: Math.max(6, parent.width * (face.now.getSeconds() / 59))
                    height: parent.height
                    radius: 1.5
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }

            // ---- Month Navigation Bar ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6

                Text {
                    text: Qt.formatDate(new Date(face.viewYear, face.viewMonth, 1, 12), "MMMM yyyy").toUpperCase()
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1.2
                    MouseArea {
                        anchors.fill: parent
                        enabled: !face.isCurrentMonth
                        onClicked: face.goToToday()
                    }
                }

                Item { Layout.fillWidth: true }

                Repeater {
                    model: [
                        { label: "󰅁", step: -1 },
                        { label: "󰅂", step: 1 }
                    ]
                    Rectangle {
                        id: navBtn
                        required property var modelData
                        width: 26; height: 26
                        radius: 13
                        color: navArea.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.07)
                        Text {
                            anchors.centerIn: parent
                            text: navBtn.modelData.label
                            color: navArea.containsMouse ? Theme.accentText : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: face.stepMonth(navBtn.modelData.step)
                        }
                    }
                }
            }

            // ---- Weekday Headers ----
            Row {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    Text {
                        required property string modelData
                        required property int index
                        width: 38
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: index >= 5 ? Theme.accent2 : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            // ---- Clean 6x7 Day Grid (NO small background squares; pill ONLY on Today / Hover!) ----
            Grid {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                columnSpacing: 4
                rowSpacing: 4

                Repeater {
                    model: face.gridCells

                    Item {
                        id: dayCell
                        required property var modelData
                        required property int index
                        width: 38
                        height: 34

                        readonly property bool isToday: modelData.isToday
                        readonly property bool inMonth: modelData.inMonth

                        Rectangle {
                            anchors.centerIn: parent
                            width: dayCell.isToday ? 34 : (dayHover.containsMouse ? 32 : 0)
                            height: dayCell.isToday ? 30 : (dayHover.containsMouse ? 28 : 0)
                            radius: 10
                            visible: dayCell.isToday || dayHover.containsMouse
                            color: dayCell.isToday
                                ? Theme.accent
                                : Qt.rgba(1, 1, 1, 0.10)
                            Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.modelData.day
                            color: dayCell.isToday
                                ? Theme.accentText
                                : (dayCell.inMonth
                                    ? (dayCell.modelData.isWeekend ? Theme.accent2 : Theme.fg)
                                    : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.26))
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.bold: dayCell.isToday || dayHover.containsMouse
                        }

                        MouseArea {
                            id: dayHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // CENTRE HUB: TURNTABLE, RADIAL SPECTRUM CROWN & LYRICS STAGE
    // =========================================================================
    Item {
        id: centerHub
        x: face.cx - width / 2
        y: 16
        width: 312
        height: face.faceH - 32
        opacity: Math.min(1, face.hubGrow * 1.4)
        scale: 0.88 + 0.12 * face.hubGrow

        Item {
            id: platterStage
            width: 248
            height: 248
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4

            // Breathing ambient halo when playing
            Rectangle {
                anchors.centerIn: parent
                width: face.isPlaying ? 232 : 204
                height: width
                radius: width / 2
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, face.isPlaying ? 0.12 : 0.04)
                Behavior on width { SpringAnimation { spring: 3.0; damping: 0.4 } }
            }

            // Counter-rotating outer tick ring (36 ticks)
            Item {
                anchors.fill: parent
                rotation: -face.idle * 9
                Repeater {
                    model: 36
                    Item {
                        required property int index
                        anchors.centerIn: parent
                        rotation: index * 10
                        Rectangle {
                            x: -1
                            y: -118
                            width: index % 3 === 0 ? 2.0 : 1.2
                            height: index % 3 === 0 ? 8 : 4
                            radius: 1
                            color: index % 3 === 0 ? Theme.accent : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.40)
                        }
                    }
                }
            }

            // 32 radial audio-reactive spectrum bars around the vinyl rim
            Item {
                anchors.fill: parent
                Repeater {
                    model: 32
                    Item {
                        required property int index
                        readonly property real rawLvl: (Audio.bars[index % 16] ?? 0) / 100
                        readonly property real lvl: face.isPlaying ? rawLvl : 0.05 + 0.03 * Math.sin(face.idle * 2.2 + index * 0.4)
                        anchors.centerIn: parent
                        rotation: index * (360 / 32)
                        Rectangle {
                            x: -1.5
                            y: -92 - parent.lvl * 22
                            width: 3
                            height: 4 + parent.lvl * 22
                            radius: 1.5
                            color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, (index % 16) / 16))
                            opacity: 0.85
                            Behavior on height { NumberAnimation { duration: 65 } }
                            Behavior on y { NumberAnimation { duration: 65 } }
                        }
                    }
                }
            }

            // Spinning Vinyl Platter
            Item {
                id: vinylDisc
                anchors.centerIn: parent
                width: 172
                height: 172
                visible: !face.showLyrics || !Lyrics.hasLyrics
                rotation: face.spinDeg

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#111318"
                    border.width: 2.2
                    border.color: face.isPlaying ? Theme.accent : Theme.accentContainer
                }
                Repeater {
                    model: [158, 144, 130]
                    Rectangle {
                        required property int modelData
                        anchors.centerIn: parent
                        width: modelData
                        height: modelData
                        radius: modelData / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.07)
                    }
                }

                Image {
                    id: rawArt
                    anchors.centerIn: parent
                    width: 120
                    height: 120
                    source: face.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: false
                }
                Item {
                    id: artCircleMask
                    width: 120
                    height: 120
                    layer.enabled: true
                    layer.smooth: true
                    visible: false
                    Rectangle { anchors.fill: parent; radius: 60 }
                }
                MultiEffect {
                    anchors.fill: rawArt
                    source: rawArt
                    visible: rawArt.status === Image.Ready
                    maskEnabled: true
                    maskSource: artCircleMask
                    maskSpreadAtMin: 1.0
                    maskThresholdMin: 0.5
                    maskThresholdMax: 1.0
                }

                Text {
                    anchors.centerIn: parent
                    visible: rawArt.status !== Image.Ready
                    text: "󰀥"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 46
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 32; height: 32; radius: 16
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
                    border.width: 2
                    border.color: Theme.accent
                    Rectangle {
                        anchors.centerIn: parent
                        width: 7; height: 7; radius: 3.5
                        color: Theme.fg
                    }
                }
            }

            // Tonearm
            Item {
                visible: vinylDisc.visible
                x: 208
                y: 34
                width: 20
                height: 20
                rotation: face.isPlaying ? 24 : 4
                Behavior on rotation { SpringAnimation { spring: 2.8; damping: 0.42 } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16; radius: 8
                    color: Theme.surface
                    border.width: 2
                    border.color: Theme.accent
                }
                Rectangle {
                    x: 8.5; y: 10
                    width: 3; height: 78
                    radius: 1.5
                    color: Theme.fgDim
                    Rectangle {
                        x: -3.5; y: 70
                        width: 10; height: 14
                        radius: 4
                        color: Theme.accent
                    }
                }
            }

            // Live 3-Line Lyrics Stage (click platter to toggle when lyrics exist)
            Rectangle {
                anchors.centerIn: parent
                width: 234
                height: 174
                radius: 20
                visible: face.showLyrics && Lyrics.hasLyrics
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                border.width: 1.4

                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "LIVE LYRICS  ·  TAP TO FLIP"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.StyledText
                        text: Lyrics.line !== "" ? Lyrics.lineHtml : "♪"
                        color: Theme.fg
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Lyrics.next !== "" ? Lyrics.next : "· · ·"
                        color: Theme.fgDim
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: Lyrics.hasLyrics
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: face.showLyrics = !face.showLyrics
            }
        }

        ColumnLayout {
            anchors {
                top: platterStage.bottom
                topMargin: 6
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            spacing: 6

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: face.player ? (face.player.trackTitle || "Unknown Track") : "Nothing Playing"
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 15
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: face.player
                    ? (face.player.trackArtist || face.player.identity || "Unknown Artist")
                    : "Start playback in any player"
                color: Theme.fgDim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 12
            }

            // Compact live lyric pill underneath
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 276
                Layout.preferredHeight: 28
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Lyrics.hasLyrics ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : "transparent"
                border.width: 1

                Text {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Lyrics.hasLyrics ? Text.StyledText : Text.PlainText
                    text: Lyrics.hasLyrics
                        ? (Lyrics.line !== "" ? Lyrics.lineHtml : "♪ Instrumental")
                        : (face.isPlaying ? "󰎆  Audio stream active" : "󰎆  Standby")
                    color: Lyrics.hasLyrics ? Theme.fg : Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: Lyrics.hasLyrics
                    onClicked: face.showLyrics = !face.showLyrics
                }
            }

            // Rounded Pill Transport Buttons
            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                spacing: 12
                opacity: face.player ? 1.0 : 0.4

                Repeater {
                    model: [
                        { icon: "󰒮", act: "prev",   w: 48 },
                        { icon: "play", act: "toggle", w: 68 },
                        { icon: "󰒭", act: "next",   w: 48 }
                    ]

                    Rectangle {
                        id: tBtn
                        required property var modelData
                        readonly property bool isMain: modelData.act === "toggle"
                        width: modelData.w
                        height: 34
                        radius: 17
                        color: tArea.containsMouse
                            ? Theme.accent
                            : (isMain ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.08))
                        border.color: isMain ? Theme.accent : "transparent"
                        border.width: isMain ? 1.2 : 0
                        scale: tArea.pressed ? 0.93 : (tArea.containsMouse ? 1.05 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

                        Text {
                            anchors.centerIn: parent
                            text: tBtn.modelData.icon === "play"
                                ? (face.isPlaying ? "󰏤" : "󰐊")
                                : tBtn.modelData.icon
                            color: tArea.containsMouse
                                ? Theme.accentText
                                : (tBtn.isMain ? Theme.accent : Theme.fg)
                            font.family: Theme.font
                            font.pixelSize: tBtn.isMain ? 20 : 17
                        }

                        MouseArea {
                            id: tArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const p = face.player;
                                if (!p) return;
                                if (tBtn.modelData.act === "prev") p.previous();
                                else if (tBtn.modelData.act === "next") p.next();
                                else p.togglePlaying();
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // RIGHT WING: AUTO-SCALING TELEMETRY SPARKLINES & LIQUID ORB GAUGES
    // =========================================================================
    Item {
        id: rightWing
        x: face.faceW - width - 22 - (1 - face.wingR) * 110
        y: 18
        width: 294
        height: face.faceH - 36
        opacity: Math.min(1, face.wingR * 1.4)
        scale: 0.90 + 0.10 * face.wingR

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            // ---- Telemetry Header + CPU Temp Pill (NO twisted sliver!) ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: "Telemetry"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Text {
                        text: face.uptime !== "" ? ("Up " + face.uptime) : "Live sensors"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: face.cpuTemp > 0
                    width: 66; height: 26
                    radius: 13
                    color: face.cpuTemp >= 78 ? Theme.warn : Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.16)
                    border.color: face.cpuTemp >= 78 ? Theme.warn : Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.5)
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "󰔏 " + face.cpuTemp + "°C"
                        color: face.cpuTemp >= 78 ? Theme.accentText : Theme.accent2
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            // ---- Dual Auto-Scaling Sparkline Stage (Pocket-Dots style) ----
            Rectangle {
                id: graphCard
                Layout.fillWidth: true
                Layout.preferredHeight: 196
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.05)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                Canvas {
                    id: graphCanvas
                    anchors { fill: parent; margins: 12 }
                    antialiasing: true

                    function drawBand(ctx, arr, ceil, y0, h, col) {
                        const w = width;
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06);
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(0, y0 + h);
                        ctx.lineTo(w, y0 + h);
                        ctx.stroke();

                        if (!arr || arr.length < 2) return;
                        const n = arr.length;
                        const stepX = w / Math.max(1, n - 1);

                        ctx.beginPath();
                        ctx.moveTo(0, y0 + h);
                        for (let i = 0; i < n; i++) {
                            const px = i * stepX;
                            const py = y0 + h - Math.min(1, arr[i] / ceil) * (h - 18);
                            ctx.lineTo(px, py);
                        }
                        ctx.lineTo((n - 1) * stepX, y0 + h);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.14);
                        ctx.fill();

                        ctx.beginPath();
                        for (let i = 0; i < n; i++) {
                            const px = i * stepX;
                            const py = y0 + h - Math.min(1, arr[i] / ceil) * (h - 18);
                            if (i === 0) ctx.moveTo(px, py);
                            else ctx.lineTo(px, py);
                        }
                        ctx.strokeStyle = col;
                        ctx.lineWidth = 2.0;
                        ctx.stroke();

                        const idx = (face.hoverSample >= 0 && face.hoverSample < n) ? face.hoverSample : (n - 1);
                        const tx = idx * stepX;
                        const ty = y0 + h - Math.min(1, arr[idx] / ceil) * (h - 18);

                        if (face.hoverSample >= 0) {
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(tx, y0 + 14);
                            ctx.lineTo(tx, y0 + h);
                            ctx.stroke();
                        }

                        ctx.beginPath();
                        ctx.arc(tx, ty, 4, 0, Math.PI * 2);
                        ctx.fillStyle = col;
                        ctx.fill();
                        ctx.lineWidth = 1.5;
                        ctx.strokeStyle = Theme.bg;
                        ctx.stroke();
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const bandH = height / 2 - 4;
                        drawBand(ctx, face.cpuHist, face.cpuCeil, 0, bandH, Theme.accent);
                        drawBand(ctx, face.memHist, face.memCeil, bandH + 8, bandH, Theme.accent2);
                    }
                }

                Text {
                    x: 14; y: 8
                    text: "CPU · max " + face.cpuCeil + "%"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.bold: true
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 6 }
                    text: (face.hoverSample >= 0 && face.hoverSample < face.cpuHist.length)
                        ? (face.cpuHist[face.hoverSample].toFixed(1) + "% (-" + Math.round((face.cpuHist.length - 1 - face.hoverSample) * 1.5) + "s)")
                        : (Math.round(face.cpu * 100) + "%")
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    x: 14; y: parent.height / 2 + 4
                    text: "RAM · max " + face.memCeil + "%"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.bold: true
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: parent.height / 2 + 2 }
                    text: (face.hoverSample >= 0 && face.hoverSample < face.memHist.length)
                        ? (face.memHist[face.hoverSample].toFixed(1) + "%")
                        : (Math.round(face.mem * 100) + "%")
                    color: Theme.accent2
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: graphCanvas
                    hoverEnabled: true
                    onPositionChanged: mouse => {
                        const n = face.cpuHist.length;
                        if (n < 2) { face.hoverSample = -1; return; }
                        face.hoverSample = Math.max(0, Math.min(n - 1, Math.round(mouse.x / width * (n - 1))));
                        graphCanvas.requestPaint();
                    }
                    onExited: {
                        face.hoverSample = -1;
                        graphCanvas.requestPaint();
                    }
                }
            }

            // ---- Four Rippling LiquidOrb Gauges (CPU, RAM, Disk, Battery) ----
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Repeater {
                    model: [
                        { val: face.cpu,  col: Theme.accent,  lbl: "CPU" },
                        { val: face.mem,  col: Theme.accent2, lbl: "RAM" },
                        { val: face.disk, col: face.disk > 0.9 ? Theme.warn : Theme.accentContainer, lbl: "Disk" },
                        {
                            val: face.hasBattery ? face.battery.percentage : 1.0,
                            col: face.hasBattery && face.battery.percentage < 0.2 ? Theme.warn : Theme.good,
                            lbl: face.hasBattery
                                ? (face.battery.state === UPowerDeviceState.Charging ? "Chg" : "Bat")
                                : "AC"
                        }
                    ]
                    Item {
                        id: orbSlot
                        required property var modelData
                        width: 66
                        height: 88
                        LiquidOrb {
                            anchors.centerIn: parent
                            scale: 0.82
                            value: orbSlot.modelData.val
                            color: orbSlot.modelData.col
                            label: orbSlot.modelData.lbl
                        }
                    }
                }
            }
        }
    }
}
