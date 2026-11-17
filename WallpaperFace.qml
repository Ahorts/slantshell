import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import "widgets"

// Wallpaper face of the island: a film strip pulled between two gear dials. The island drops from the bar to the
// middle of the screen and stretches into a wide band; the dials spin up as they appear and the strip unrolls from
// the centre; a toothed dial sits at each end, and a strip of wallpapers runs between them with the selected one big
// in the middle. Scroll (or use the arrow keys) and both dials turn, the sprocket holes run along the strip, and
// the cards are drawn out of one dial and wound into the other, all on one spring. Enter applies (through skwd, so
// videos and Workshop items work too) and the shell and Hyprland recolour to match. Esc closes.
// Lists skwd's whole library, most recently used first; without skwd it falls back to ~/Pictures/Wallpapers.
Item {
    id: face

    property bool active: false              // true while this face is the one showing
    signal closeRequested()
    property real availW: 1240                // room between the bar's side panels (set by the island)

    readonly property real faceW: Math.max(820, availW)        // the whole width of the screen
    readonly property real faceH: 380
    readonly property real cx: width / 2
    readonly property real cy: 186
    readonly property real gearR: 168

    // ---- library ----
    ListModel { id: lib }
    function wrap(i) { return ((i % lib.count) + lib.count) % lib.count; }
    function thumbAt(i) { return lib.count > 0 ? lib.get(wrap(i)).thumb : ""; }
    function kindAt(i) { return lib.count > 0 ? lib.get(wrap(i)).kind : "image"; }

    onActiveChanged: if (active) { if (lib.count === 0) listProc.running = true; }
    onVisibleChanged: if (visible && active) Qt.callLater(() => keys.forceActiveFocus())

    Process {
        id: listProc
        command: ["skwd-helm", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let items = [];
                try {
                    items = JSON.parse(text).wallpapers.filter(w => !w.hidden && (w.thumb || w.path)).map(w => ({
                        key: w.key,
                        kind: w.type === "static" ? "image" : (w.type === "video" ? "video" : "workshop"),
                        thumb: w.thumb || w.path,
                        wpath: w.path || "",
                        recent: Number(w.last_applied) || 0
                    }));
                } catch (e) { console.warn("WallpaperFace: could not read skwd's library:", e); }
                items.sort((a, b) => b.recent - a.recent);
                if (items.length === 0) { fallback.running = true; return; }
                lib.clear();
                for (const it of items) lib.append(it);
            }
        }
        onExited: (code, status) => { if (code !== 0) fallback.running = true; }
    }
    Process {
        id: fallback
        command: ["sh", "-c", "find \"$HOME/Pictures/Wallpapers\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                lib.clear();
                for (const p of text.split("\n").filter(l => l !== "")) lib.append({ key: p, kind: "image", thumb: p, wpath: p, recent: 0 });
            }
        }
    }

    Process { id: applyProc }
    function applyCurrent() {
        if (lib.count === 0) return;
        const it = lib.get(wrap(Math.round(posTarget)));
        applyProc.command = ["skwd-helm", "apply", it.kind === "image" ? it.wpath : it.key];
        applyProc.running = true;
        Theme.generateFrom(it.thumb);
        spark(1);
        closeLater.restart();
    }

    Timer { id: closeLater; interval: 260; onTriggered: face.closeRequested() }

    // ---- the strip's position: everything (cards, holes, both dials) hangs off this one spring ----
    property real posTarget: 0
    property real pos: posTarget
    Behavior on pos { SpringAnimation { spring: 4.2; damping: 0.46; epsilon: 0.004 } }
    readonly property int base: Math.round(pos)
    function turn(by) { posTarget += by; }
    property int forceTurn: 0                 // each change turns one step (`ipc call wallpapers turn`)
    onForceTurnChanged: if (active) turn(1)

    // idle motion: the strip creeps along and the dials tick over even when you are not scrolling
    property real idle: 0
    FrameAnimation { running: face.active && face.visible; onTriggered: face.idle += Math.min(frameTime, 0.05) }
    readonly property int holeCount: Math.ceil(width / 34) + 2      // enough sprocket holes for the whole width

    property real appear: active ? 1 : 0
    Behavior on appear { SpringAnimation { spring: 2.4; damping: 0.36; epsilon: 0.002 } }

    // where a card sits, how big it is, by its distance from the middle (in cards)
    readonly property var xTab: [0, 305, 511, 669, 827, 985]
    readonly property var sTab: [1, 0.7, 0.42, 0.42, 0.42, 0.42]
    function lerpTab(tab, a) {
        const aa = Math.max(0, Math.min(tab.length - 1.001, a));
        const i = Math.floor(aa);
        return tab[i] + (tab[i + 1] - tab[i]) * (aa - i);
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) face.closeRequested();
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_K) face.turn(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_J || event.key === Qt.Key_Tab) face.turn(1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) face.applyCurrent();
            else return;
            event.accepted = true;
        }
    }
    WheelHandler { onWheel: event => face.turn(event.angleDelta.y > 0 ? -1 : 1) }

    // ---- the strip: two rails with sprocket holes that run with the cards ----
    Repeater {
        model: 2
        Item {
            required property int index
            readonly property real railY: index === 0 ? face.cy - 126 : face.cy + 112
            opacity: Math.min(1, face.appear)
            transform: Scale { origin.x: face.cx; xScale: Math.max(0.001, face.appear) }
            Rectangle { x: 0; y: railY; width: face.width; height: 14; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.35) }
            Rectangle { x: 0; y: railY; width: face.width; height: 1; color: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.7) }
            Rectangle { x: 0; y: railY + 13; width: face.width; height: 1; color: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.7) }
            Repeater {
                model: face.holeCount
                Rectangle {
                    required property int index
                    antialiasing: true
                    readonly property real total: face.holeCount * 34
                    x: (((index * 34 - face.pos * 305 - face.idle * 16) % total) + total) % total - 20
                    y: railY + 4
                    width: 12
                    height: 6
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                }
            }
        }
    }

    // ---- the cards ----
    Repeater {
        model: 9

        Item {
            id: card
            required property int index
            readonly property int d: index - 4
            readonly property int itemIdx: face.base + d
            readonly property real dd: d - (face.pos - face.base)      // distance from the middle, in cards
            readonly property real ad: Math.abs(dd)
            readonly property real xoff: face.lerpTab(face.xTab, ad)
            readonly property bool isSel: ad < 0.5

            property real grow: face.active ? 1 : 0
            Behavior on grow {
                SequentialAnimation {
                    PauseAnimation { duration: face.active ? 120 + Math.abs(card.d) * 70 : 0 }
                    SpringAnimation { spring: 4.0; damping: 0.45; epsilon: 0.002 }
                }
            }

            // sized directly instead of scaled, so the border stays a real 1.5px line (a scaled 1px border breaks
            // up into dashes) and the rotated edges are antialiased
            readonly property real sc: face.lerpTab(face.sTab, ad) * Math.min(1, 0.5 + grow * 0.5)
            width: 340 * sc
            height: 200 * sc
            x: face.cx + (dd < 0 ? -xoff : xoff) * Math.min(1.06, grow) - width / 2
            y: face.cy - 6 - height / 2 + ad * ad * 4
            rotation: dd * 2.5
            antialiasing: true
            // wound into the dials: fades as it reaches them
            opacity: Math.max(0, Math.min(1, (face.width / 2 - 20 - xoff) / 110)) * Math.min(1, grow * 1.6)
            z: 10 - ad
            visible: opacity > 0.01 && lib.count > 0

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                border.color: card.isSel ? Theme.accent : Theme.accentContainer
                border.width: card.isSel ? 3 : 1.5
                antialiasing: true
            }
            Image {
                anchors { fill: parent; margins: card.isSel ? 3 : 1.5 }
                antialiasing: true
                mipmap: true
                source: { const t = face.thumbAt(card.itemIdx); return t ? "file://" + t : ""; }
                sourceSize.width: 520
                sourceSize.height: 310
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Rectangle {
                visible: face.kindAt(card.itemIdx) !== "image"
                anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 10 }
                width: tag.implicitWidth + 14
                height: 20
                color: Qt.rgba(0, 0, 0, 0.65)
                Text {
                    id: tag
                    anchors.centerIn: parent
                    text: face.kindAt(card.itemIdx) === "video" ? "VIDEO" : "WORKSHOP"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.5
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { if (card.isSel) face.applyCurrent(); else face.turn(card.d); }
            }
        }
    }

    // ---- the two dials: they turn with the strip, and the cards disappear behind them ----
    component Gear: Item {
        id: gear
        property int spinDir: 1
        width: 1; height: 1
        z: 30
        scale: Math.max(0.01, face.appear)
        // solid disc so the strip and cards pass behind it
        Rectangle { x: -face.gearR; y: -face.gearR; width: face.gearR * 2; height: width; radius: face.gearR; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.9); border.color: Theme.accent; border.width: 2 }
        Item {
            rotation: face.pos * 42 + face.idle * 2.2 + (1 - face.appear) * (gear.spinDir * 540)
            Repeater {      // teeth
                model: 24
                Rectangle {
                    required property int index
                    antialiasing: true
                    x: face.gearR - 4
                    y: -5
                    width: 14
                    height: 10
                    color: index % 6 === 0 ? Theme.accent : Theme.accentContainer
                    transform: Rotation { origin.x: -(face.gearR - 4); origin.y: 5; angle: index * 15 }
                }
            }
            Repeater {      // tick marks, like a clock face
                model: 60
                Rectangle {
                    required property int index
                    antialiasing: true
                    readonly property bool major: index % 5 === 0
                    x: face.gearR - 22 - (major ? 10 : 4)
                    y: -0.75
                    width: major ? 10 : 4
                    height: 1.5
                    color: major ? Theme.accent : Theme.fgDim
                    opacity: major ? 0.9 : 0.5
                    transform: Rotation { origin.x: -(face.gearR - 22 - (major ? 10 : 4)); origin.y: 0.75; angle: index * 6 }
                }
            }
            Repeater {      // spokes
                model: 3
                Rectangle {
                    required property int index
                    antialiasing: true
                    x: 14; y: -2; width: face.gearR - 50; height: 4
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                    transform: Rotation { origin.x: -14; origin.y: 2; angle: index * 120 }
                }
            }
        }
        Rectangle { x: -86; y: -86; width: 172; height: 172; radius: 86; color: "transparent"; border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.18); border.width: 1 }
        // the dial's own life: an inner ring of ticks turning the other way, two hands sweeping like a clock,
        // and a hub that pulses
        Item {
            rotation: -face.idle * 14 - face.pos * 20
            Repeater {
                model: 36
                Rectangle {
                    required property int index
                    antialiasing: true
                    x: 70; y: -1; width: index % 3 === 0 ? 12 : 6; height: 2
                    color: index % 3 === 0 ? Theme.accent2 : Theme.fgDim
                    opacity: 0.8
                    transform: Rotation { origin.x: -70; origin.y: 1; angle: index * 10 }
                }
            }
        }
        Rectangle {     // long hand
            antialiasing: true
            x: 0; y: -1.5; width: face.gearR - 34; height: 3; radius: 1.5
            color: Theme.accent
            transform: Rotation { origin.x: 0; origin.y: 1.5; angle: face.idle * 45 + face.pos * 90 }
        }
        Rectangle {     // short hand
            antialiasing: true
            x: 0; y: -2.5; width: 62; height: 5; radius: 2.5
            color: Theme.accent2
            transform: Rotation { origin.x: 0; origin.y: 2.5; angle: -90 + face.idle * 6 + face.pos * 30 }
        }
        Rectangle {
            readonly property real r: 14 + Math.sin(face.idle * 3) * 2.5
            x: -r; y: -r; width: r * 2; height: r * 2; radius: r; color: Theme.accent
        }
    }
    // they roll outward from the centre to the two ends as the strip opens
    // (they end up centred on the screen edges, so half of each dial shows)
    Gear { spinDir: -1; x: face.cx - face.cx * Math.min(1.01, face.appear); y: face.cy - 6 }
    Gear { spinDir: 1; x: face.cx + face.cx * Math.min(1.01, face.appear); y: face.cy - 6 }

    // ---- lightning on the edges ----
    // A faint current always runs around both dial rims and along the film rails; turning the strip flares it up
    // (`spark()`), applying flares it fully. See widgets/EdgeSpark.qml.
    signal sparked(real amount)
    function spark(amount) {
        for (const e of [rimL, rimR, railT, railB]) e.burst(amount);
        sparked(amount);
    }
    onPosTargetChanged: if (active) spark(0.7)
    EdgeSpark {
        id: rimL
        z: 31
        anchors.fill: parent
        visible: face.appear > 0.6
        ring: true
        cx: face.cx - face.cx * Math.min(1.01, face.appear); cy: face.cy - 6
        r: face.gearR + 1
        intensity: 0.22
    }
    EdgeSpark {
        id: rimR
        z: 31
        anchors.fill: parent
        visible: face.appear > 0.6
        ring: true
        cx: face.cx + face.cx * Math.min(1.01, face.appear); cy: face.cy - 6
        r: face.gearR + 1
        intensity: 0.22
    }
    EdgeSpark {
        id: railT
        z: 5
        anchors.fill: parent
        visible: face.appear > 0.6
        points: [[0, face.cy - 126], [face.width, face.cy - 126]]
        intensity: 0.12
        speed: 0.7
    }
    EdgeSpark {
        id: railB
        z: 5
        anchors.fill: parent
        visible: face.appear > 0.6
        points: [[0, face.cy + 125], [face.width, face.cy + 125]]
        intensity: 0.12
        speed: 0.7
    }

    // ---- counter ----
    Text {
        z: 31
        anchors.horizontalCenter: parent.horizontalCenter
        y: face.faceH - 34
        opacity: Math.min(1, face.appear)
        text: lib.count > 0 ? (face.wrap(Math.round(face.posTarget)) + 1) + " / " + lib.count : "…"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
}
