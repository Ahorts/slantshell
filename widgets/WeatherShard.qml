import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import ".."

// Weather on the desktop, as a slanted glass shard that sits under the clock.
//   left    a drawn icon for the conditions (sun, moon, clouds, rain, storm, snow, fog); it comes alive for a few
//           seconds whenever the weather refreshes and while you hover it, and is still otherwise
//   middle  the temperature (rolls into place), the conditions, feels-like, today's high/low, the place
//   bottom  the next hours: a small temperature curve with five 3-hourly forecast points
// Data: wttr.in (`?format=j1`; it works out the location from your IP), every 20 minutes. The last answer is cached
// in ~/.local/state/slantshell/weather.json, so it shows straight away after a restart.
Item {
    id: root
    width: 440
    height: 176

    readonly property string cachePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slantshell/weather.json"
    property var w: null                      // parsed wttr.in j1
    readonly property var cur: w ? w.current_condition[0] : null
    readonly property var today: w ? w.weather[0] : null
    readonly property string place: w ? w.nearest_area[0].areaName[0].value : ""
    readonly property int code: cur ? Number(cur.weatherCode) : 113
    readonly property bool night: {
        if (!today) return false;
        const a = today.astronomy[0];
        const toMin = s => { const m = s.match(/(\d+):(\d+)\s*(AM|PM)/); if (!m) return 0; let h = Number(m[1]) % 12; if (m[3] === "PM") h += 12; return h * 60 + Number(m[2]); };
        const n = new Date(), mins = n.getHours() * 60 + n.getMinutes();
        return mins < toMin(a.sunrise) || mins > toMin(a.sunset);
    }
    // conditions -> one of: clear, partly, cloud, fog, rain, storm, snow
    function kindOf(c) {
        if (c === 113) return "clear";
        if (c === 116) return "partly";
        if (c === 119 || c === 122) return "cloud";
        if ([143, 248, 260].includes(c)) return "fog";
        if ([200, 386, 389, 392, 395].includes(c)) return "storm";
        if ([179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377, 182, 185, 281, 284, 311, 314, 317, 350, 362, 365].includes(c)) return "snow";
        return "rain";
    }
    readonly property string kind: kindOf(code)
    function glyph(k, isNight) {
        return ({ clear: isNight ? "󰖔" : "󰖙", partly: isNight ? "󰼱" : "󰖕", cloud: "󰖐", fog: "󰖑", rain: "󰖗", storm: "󰙾", snow: "󰖘" })[k];
    }
    // next 12 hours: four 3-hourly slots after now (today, then tomorrow)
    readonly property var nextSlots: {
        if (!w) return [];
        const now = new Date(), out = [];
        for (let d = 0; d < Math.min(2, w.weather.length) && out.length < 5; d++)
            for (const h of w.weather[d].hourly) {
                const hr = Number(h.time) / 100 + d * 24;
                if (hr > now.getHours() && out.length < 5) out.push({ hr: hr % 24, t: Number(h.tempC), k: kindOf(Number(h.weatherCode)), night: (hr % 24) < 6 || (hr % 24) >= 18 });
            }
        return out;
    }

    // ---- fetching ----
    FileView {
        id: cache
        path: root.cachePath
        printErrors: false
        onLoaded: { try { root.w = JSON.parse(cache.text()); } catch (e) {} }
    }
    Process { id: mk; command: ["mkdir", "-p", root.cachePath.replace(/\/[^\/]*$/, "")] }
    Process {
        id: fetch
        command: ["curl", "-s", "--max-time", "15", "https://wttr.in/?format=j1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    if (j.current_condition) { root.w = j; mk.running = true; cache.setText(text); root.wake(); }
                } catch (e) {}
            }
        }
    }
    Timer { interval: 20 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: fetch.running = true }

    // the icon comes alive for a few seconds after an update, and while hovered
    property bool lively: hover.hovered || wakeTimer.running
    function wake() { wakeTimer.restart(); }
    Timer { id: wakeTimer; interval: 5000 }
    HoverHandler { id: hover }

    // ---- the shard ----
    // Same slope as the clock's shard (34 px over 204), and placed so its left and right edges carry straight on
    // from the clock's across the gap between them (4 px below the clock's shard + the column's 12 px spacing):
    // the two read as one shard split in two.
    readonly property real slope: 34 / 204
    readonly property real gapAbove: 16
    readonly property real slant: 168 * slope
    Shape {
        id: shard
        x: 6 - root.gapAbove * root.slope - root.slant
        y: 0
        width: (406 - 34 - root.gapAbove * root.slope) - x
        height: 168
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

    // ---- the icon ----
    Item {
        id: icon
        x: shard.x + root.slant + 18
        y: 14
        width: 76; height: 70
        readonly property bool showSun: root.kind === "clear" || root.kind === "partly"
        readonly property bool showCloud: root.kind !== "clear"
        readonly property color cloudCol: root.kind === "storm" || root.kind === "rain" ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.78) : Theme.fg

        // sun (or moon at night), behind the cloud
        Item {
            id: sun
            visible: icon.showSun
            readonly property real cx: root.kind === "clear" ? 38 : 26
            readonly property real cy: root.kind === "clear" ? 35 : 24
            readonly property real r: root.kind === "clear" ? 17 : 13
            // rays: turn slowly while lively
            Item {
                visible: !root.night
                x: sun.cx; y: sun.cy
                property real spin: 0
                rotation: spin
                NumberAnimation on spin { running: root.lively && !root.night; from: 0; to: 360; duration: 9000; loops: Animation.Infinite }
                Repeater {
                    model: 8
                    Rectangle {
                        required property int index
                        x: -1.5; y: -sun.r - 11
                        width: 3; height: 7; radius: 1.5
                        color: Theme.accent
                        antialiasing: true
                        transform: Rotation { origin.x: 1.5; origin.y: sun.r + 11; angle: index * 45 }
                    }
                }
            }
            Rectangle {
                visible: !root.night
                x: sun.cx - sun.r; y: sun.cy - sun.r
                width: sun.r * 2; height: width; radius: sun.r
                color: Theme.accent
                antialiasing: true
                // a soft glow that breathes while lively
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * (1.5 + 0.2 * glowB.v); height: width; radius: width / 2; z: -1
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    QtObject { id: glowB; property real v: 0 }
                    SequentialAnimation {
                        running: root.lively; loops: Animation.Infinite
                        NumberAnimation { target: glowB; property: "v"; to: 1; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { target: glowB; property: "v"; to: 0; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }
            }
            // moon: a crescent
            Shape {
                visible: root.night
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.accent
                    strokeColor: "transparent"
                    startX: sun.cx + 2; startY: sun.cy - sun.r
                    PathArc { x: sun.cx + 2; y: sun.cy + sun.r; radiusX: sun.r; radiusY: sun.r; direction: PathArc.Counterclockwise }
                    PathArc { x: sun.cx + 2; y: sun.cy - sun.r; radiusX: sun.r * 0.78; radiusY: sun.r; direction: PathArc.Clockwise }
                }
            }
        }
        // cloud: overlapping discs on a flat base, drifting a little while lively
        Item {
            id: cloud
            visible: icon.showCloud
            property real drift: 0
            SequentialAnimation on drift {
                running: root.lively; loops: Animation.Infinite
                NumberAnimation { to: 3; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { to: -3; duration: 1600; easing.type: Easing.InOutSine }
            }
            x: drift
            Rectangle { x: 14; y: 30; width: 22; height: 22; radius: 11; color: icon.cloudCol; antialiasing: true }
            Rectangle { x: 26; y: 20; width: 30; height: 30; radius: 15; color: icon.cloudCol; antialiasing: true }
            Rectangle { x: 44; y: 30; width: 22; height: 22; radius: 11; color: icon.cloudCol; antialiasing: true }
            Rectangle { x: 18; y: 38; width: 42; height: 14; radius: 7; color: icon.cloudCol; antialiasing: true }
        }
        // rain / snow: falling while lively, resting in place otherwise
        Repeater {
            model: (root.kind === "rain" || root.kind === "storm" || root.kind === "snow") ? 5 : 0
            Rectangle {
                id: drop
                required property int index
                readonly property bool flake: root.kind === "snow"
                property real fall: (index * 0.37) % 1
                NumberAnimation on fall { running: root.lively; from: 0; to: 1; duration: drop.flake ? 1600 : 700; loops: Animation.Infinite }
                x: 20 + index * 9 - fall * (flake ? 0 : 4)
                y: 54 + fall * 14
                width: flake ? 4 : 2; height: flake ? 4 : 7; radius: flake ? 2 : 1
                color: flake ? Theme.fg : Theme.accent2
                opacity: 1 - fall * 0.8
                antialiasing: true
            }
        }
        // storm: a bolt that flashes now and then while lively
        Shape {
            visible: root.kind === "storm"
            preferredRendererType: Shape.CurveRenderer
            opacity: boltFlash.on ? 1 : 0.55
            ShapePath {
                fillColor: Theme.warn
                strokeColor: "transparent"
                startX: 40; startY: 44
                PathLine { x: 32; y: 58 }
                PathLine { x: 38; y: 58 }
                PathLine { x: 34; y: 70 }
                PathLine { x: 46; y: 53 }
                PathLine { x: 40; y: 53 }
                PathLine { x: 44; y: 44 }
            }
        }
        QtObject { id: boltFlash; property bool on: false }
        Timer { running: root.lively && root.kind === "storm"; interval: 1400; repeat: true; onTriggered: { boltFlash.on = true; boltOff.restart(); } }
        Timer { id: boltOff; interval: 120; onTriggered: boltFlash.on = false }
        // fog: three drifting lines
        Repeater {
            model: root.kind === "fog" ? 3 : 0
            Rectangle {
                required property int index
                x: 14 + (index % 2) * 8 + cloud.drift * (index % 2 ? -1 : 1); y: 56 + index * 6
                width: 46; height: 3; radius: 1.5
                color: Theme.fgDim
            }
        }
    }

    // ---- now ----
    Column {
        x: icon.x + icon.width + 14
        y: 12
        spacing: 1
        Row {
            spacing: 10
            RollText {
                text: root.cur ? root.cur.temp_C + "°" : "--"
                color: Theme.fg
                font: Qt.font({ family: Theme.font, pixelSize: 46, bold: true, italic: true })
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: root.cur ? root.cur.weatherDesc[0].value.toLowerCase() : "fetching weather…"
                    color: Theme.accent
                    font.family: Theme.font; font.pixelSize: 13; font.bold: true
                    width: 190; elide: Text.ElideRight
                }
                Text {
                    text: root.cur && root.today ? "feels " + root.cur.FeelsLikeC + "°  ·  ↑" + root.today.maxtempC + "°  ↓" + root.today.mintempC + "°" : ""
                    color: Theme.fgDim
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
        Text {
            text: root.place !== "" && root.cur ? "󰍎 " + root.place + "   ·   󰖎 " + root.cur.humidity + "%   ·   󰖝 " + root.cur.windspeedKmph + " km/h" : ""
            color: Theme.fgDim
            opacity: 0.8
            font.family: Theme.font; font.pixelSize: 10
        }
    }

    // ---- next 12 hours: a small curve with four points ----
    Item {
        id: fc
        x: shard.x + root.slant + 4
        y: 104
        width: 330; height: 56
        readonly property var pts: {
            const s = root.nextSlots;
            if (s.length < 2) return [];
            const ts = s.map(q => q.t), lo = Math.min(...ts), hi = Math.max(...ts), span = Math.max(1, hi - lo);
            return s.map((q, i) => ({ x: 20 + i * (width - 40) / (s.length - 1), y: 6 + (1 - (q.t - lo) / span) * 14, q: q }));
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: fc.pts.length > 1
            ShapePath {
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
                strokeWidth: 1.5
                fillColor: "transparent"
                startX: fc.pts.length ? fc.pts[0].x : 0; startY: fc.pts.length ? fc.pts[0].y : 0
                PathPolyline { path: fc.pts.map(p => Qt.point(p.x, p.y)) }
            }
        }
        Repeater {
            model: fc.pts
            Item {
                required property var modelData
                required property int index
                x: modelData.x; y: modelData.y
                Rectangle { x: -3; y: -3; width: 6; height: 6; radius: 3; color: index === 0 ? Theme.accent : Theme.bg; border.color: Theme.accent; border.width: 1.2; antialiasing: true }
                // icon and temperature as separate pieces with a real gap (icon glyphs overhang their advance width)
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    spacing: 6
                    Text {
                        text: root.glyph(modelData.q.k, modelData.q.night)
                        color: Theme.fg
                        font.family: Theme.font; font.pixelSize: 11; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.q.t + "°"
                        color: Theme.fg
                        font.family: Theme.font; font.pixelSize: 11; font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    text: (modelData.q.hr < 10 ? "0" : "") + modelData.q.hr + ":00"
                    color: Theme.fgDim
                    font.family: Theme.font; font.pixelSize: 9
                }
            }
        }
    }
}
