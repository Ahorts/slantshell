import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// Top bar made of three floating parallelogram panels (skwd-style slanted edges) inside ONE
// fixed-size, click-through surface:
//   left   (permanent): launcher button + workspaces
//   centre (the island): notifications (widen to a one-line preview), else the playing media
//                        (controls on hover), else the active window title
//   right  (permanent): system tray, volume, battery, clock
//
// The surface never resizes. Only the panels animate inside it, which keeps motion smooth
// (resizing a layer-shell window every frame forces a compositor round trip).
PanelWindow {
    id: bar

    signal launcherClicked()
    signal connectivityClicked()

    // ---- faces ----
    // The island reshapes itself into a sculpted rounded notch for the dashboard (`radiusB: 28`), while the
    // circular app switcher and orbital Wi-Fi/Bluetooth constellation float free in the middle of the screen.
    property string face: ""
    signal faceCloseRequested()
    // faces open on the focused screen only (SLANT_TEST_ANYSCREEN=1 lets them open everywhere, for testing on a virtual monitor)
    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property string faceKey: onFocusedScreen ? face : ""
    property string shownFace: ""             // the face whose content is on show right now
    readonly property bool faceShowing: faceKey !== "" || shownFace !== ""
    onFaceShowingChanged: { if (faceShowing) Theme.faceScreen = screen?.name ?? ""; else if (Theme.faceScreen === screen?.name) Theme.faceScreen = ""; }
    property real faceAlpha: 0
    readonly property bool restVisible: shownFace === "" && faceKey === ""
    readonly property real faceW: faceKey === "dashboard" ? faceDash.faceW : 0
    readonly property real faceH: faceKey === "dashboard" ? faceDash.faceH : 0
    readonly property bool faceRadial: false
    readonly property bool faceDims: false
    readonly property real faceContentOpacity: faceAlpha * island.fit
    // content leaves in 110 ms, the new face arrives over 210 ms
    onFaceKeyChanged: { faceEverHovered = false; faceSwap.restart(); }
    SequentialAnimation {
        id: faceSwap
        NumberAnimation { target: bar; property: "faceAlpha"; to: 0; duration: 110 }
        ScriptAction { script: bar.shownFace = bar.faceKey }
        NumberAnimation { target: bar; property: "faceAlpha"; to: bar.faceKey === "" ? 0 : 1; duration: 210 }
    }
    // the dashboard and Wi-Fi panel close shortly after the pointer leaves
    property bool faceEverHovered: false
    Timer {
        interval: bar.faceEverHovered ? 900 : 3500
        running: (bar.faceKey === "dashboard" || bar.faceKey === "connectivity") && !islandHover.hovered && Quickshell.env("SLANT_TEST_ANYSCREEN") !== "1"
        onTriggered: bar.faceCloseRequested()
    }
    // the launcher dims the screen on its own, slower timeline; clicking the dim closes it
    property real dimLevel: faceDims ? 1 : 0
    Behavior on dimLevel { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    signal dashboardClicked()

    readonly property int gap: 8
    readonly property int pillHeight: 40
    readonly property int smooth: 320
    readonly property int skew: 14

    // The surface covers the screen (the island can grow into a big panel anywhere in it), but only the panels, and
    // the dimming backdrop while the launcher is open, take input. The bar's reserved strip comes from BarZone.qml.
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-desktop-bar"
    WlrLayershell.keyboardFocus: faceDims ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // Only the panels take input; the rest of the surface is click-through.
    mask: Region {
        regions: [
            Region { item: leftPill },
            Region { item: island },
            Region { item: musicChip },
            Region { item: bar.faceDims ? backdrop : null },
            Region { item: rightPill }
        ]
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // Entrance: the three panels drop in one after another.
    property real introL: 0
    property real introC: 0
    property real introR: 0
    ParallelAnimation {
        id: intro
        running: true
        NumberAnimation { target: bar; property: "introL"; to: 1; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        SequentialAnimation {
            PauseAnimation { duration: 130 }
            NumberAnimation { target: bar; property: "introC"; to: 1; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 260 }
            NumberAnimation { target: bar; property: "introR"; to: 1; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
    }

    Process { id: wsSwitch }
    // Scroll over the workspaces to move between them: up = previous, down = next. Goes through empty workspaces
    // too (1..10), not only the ones that have windows.
    property real wheelAccum: 0
    function stepWorkspace(delta) {
        const cur = Hyprland.focusedWorkspace?.id ?? 1;
        const n = Math.max(1, Math.min(10, cur + (delta > 0 ? 1 : -1)));
        if (n !== cur) gotoWorkspace(n);
    }
    // the highest workspace with windows (or focused): one empty slot after it is offered as a "new" workspace
    readonly property int lastUsedWs: {
        let m = Hyprland.focusedWorkspace?.id ?? 1;
        for (const w of Hyprland.workspaces.values) if (w.id > m && w.id <= 9) m = w.id;
        return m;
    }
    function gotoWorkspace(n) {
        // Hyprland 0.5x uses Lua dispatchers, so go through hyprctl with the Lua form.
        wsSwitch.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + n + " })"];
        wsSwitch.running = true;
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink

    // The player that is currently playing, if any (see Audio.qml).
    readonly property var player: Audio.player
    readonly property bool mediaMode: player !== null

    // When the song changes, the island announces the full name for a few seconds, then shrinks
    // back to the small visualizer icon next to the window title.
    property bool trackFlash: false
    readonly property string trackKey: player ? (player.trackArtist + "|" + player.trackTitle) : ""
    onTrackKeyChanged: {
        if (trackKey !== "") {
            trackFlash = true;
            trackTimer.restart();
        }
    }
    Timer { id: trackTimer; interval: 4200; onTriggered: bar.trackFlash = false }

    // Notification currently shown in the island (see Notifs.qml). `shownNotif` keeps the last
    // one around so the content can fade out instead of blanking.
    readonly property var notif: Notifs.current
    readonly property bool notifMode: notif !== null
    property var shownNotif: null
    onNotifChanged: {
        if (notif !== null) {
            shownNotif = notif;
            notifDrain.restart();
        }
    }
    readonly property bool notifHasBody: shownNotif !== null && (shownNotif.body ?? "") !== ""
    readonly property bool notifCritical: shownNotif !== null && shownNotif.urgency === NotificationUrgency.Critical

    // Notification countdown: the island outline starts full (the two arcs meeting at the top-middle) and
    // shrinks away from the bottom, the remainder retreating toward the top-middle, as time runs out (paused while hovered). When it's gone the
    // notification goes away and the next one (if any) takes its place.
    property real notifProgress: 1
    NumberAnimation {
        id: notifDrain
        target: bar
        property: "notifProgress"
        from: 1
        to: 0
        duration: {
            const n = bar.shownNotif;
            if (!n) return 5000;
            if (n.urgency === NotificationUrgency.Critical) return 12000;
            // expireTimeout comes in milliseconds (as sent); kept between 2.5 s and 15 s so it can't stick forever
            return n.expireTimeout > 0 ? Math.max(2500, Math.min(15000, n.expireTimeout)) : 5000;
        }
        paused: bar.notifMode && islandHover.hovered
        running: bar.notifMode
        onFinished: Notifs.next()
    }

    // ---- Volume / brightness popups (shown in the island; the outline fills like a gauge) ----
    property string osdKind: ""      // "volume" | "brightness" | ""
    property real osdValue: 0
    property bool osdMuted: false
    property bool osdReady: false    // ignore the initial values reported at startup
    Timer { interval: 2500; running: true; onTriggered: bar.osdReady = true }
    Timer { id: osdTimer; interval: 1700; onTriggered: bar.osdKind = "" }
    function showOsd(kind, value, muted) {
        if (!osdReady) return;
        osdKind = kind;
        osdValue = value;
        osdMuted = muted;
        osdTimer.restart();
    }

    Connections {
        target: bar.sink?.audio ?? null
        function onVolumeChanged() { bar.showOsd("volume", bar.sink.audio.volume, bar.sink.audio.muted); }
        function onMutedChanged() { bar.showOsd("volume", bar.sink.audio.volume, bar.sink.audio.muted); }
    }

    // Brightness: read the backlight files.
    readonly property string backlight: "intel_backlight"
    property real brightness: -1
    property real brightnessMax: 1
    FileView {
        id: maxFile
        path: "/sys/class/backlight/" + bar.backlight + "/max_brightness"
        onLoaded: bar.brightnessMax = Math.max(1, Number(text()))
    }
    FileView {
        id: curFile
        path: "/sys/class/backlight/" + bar.backlight + "/brightness"
        onLoaded: {
            const v = Number(text()) / bar.brightnessMax;
            if (bar.brightness >= 0 && Math.abs(v - bar.brightness) > 0.004) bar.showOsd("brightness", v, false);
            bar.brightness = v;
        }
    }
    // The kernel announces backlight changes through udev, so react the moment it happens (no polling).
    Process {
        running: true
        command: ["udevadm", "monitor", "--kernel", "--subsystem-match=backlight"]
        stdout: SplitParser { onRead: line => { if (line.includes("backlight")) curFile.reload(); } }
    }
    // Slow safety net in case an event is missed.
    Timer { interval: 2000; running: true; repeat: true; onTriggered: curFile.reload() }

    // The island's *size* follows this instead of `view`: when a notification ends, it holds the wide shape
    // until the text has faded out, so the text fades in place instead of being dragged by a shrinking edge.
    property string layoutView: "title"
    onViewChanged: {
        if (view === "notif" || layoutView !== "notif") {
            layoutView = view;
            layoutDelay.stop();
        } else {
            layoutDelay.restart();
        }
    }
    Timer { id: layoutDelay; interval: 280; onTriggered: bar.layoutView = bar.view }

    // Gooey split: while music plays and a notification or volume popup takes over the island, a small music
    // chip separates from it (joined by a thinning neck) so the song stays visible; it merges back afterwards.
    property real split: (mediaMode && (view === "notif" || view === "osd") && faceKey === "") ? 1 : 0
    Behavior on split { NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

    // Window name vs lyrics (see titleText): a click toggles it for good, a focus change shows it briefly.
    property bool preferTitle: false
    property bool titleFlash: false
    Timer { id: titleFlashTimer; interval: 2600; onTriggered: bar.titleFlash = false }
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (!(bar.mediaMode && Lyrics.hasLyrics)) return;
            bar.titleFlash = true;
            titleFlashTimer.restart();
        }
    }

    // Which view the island is showing (priority order).
    readonly property string view: notifMode ? "notif" : (osdKind !== "" ? "osd" : ((mediaMode && (trackFlash || islandHover.hovered)) ? "media" : "title"))

    // ---- dimming backdrop (the launcher face) ----
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#000000"
        opacity: 0.55 * bar.dimLevel
        visible: bar.dimLevel > 0.002
        MouseArea { anchors.fill: parent; enabled: bar.faceDims; onClicked: bar.faceCloseRequested() }
    }

    // =========================================================== LEFT: launcher + workspaces
    SkewPanel {
        id: leftPill
        glass: true
        outlineSpark: Theme.lightning ? 0.12 : 0
        opacity: Math.min(1, bar.introL * 1.5)
        transform: Translate { y: (1 - bar.introL) * -70 }
        x: 0
        y: bar.gap                            // floats level with the island; only the outer side touches the screen edge
        height: bar.pillHeight
        skewL: 0                               // outer edge is straight (it is the screen edge)
        skewR: -bar.skew                       // inner edge leans "\\"
        strokeLeft: false
        width: leftRow.implicitWidth + bar.skew + 28
        Behavior on width { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }

        // Mouse wheel / touchpad scroll over the workspaces switches workspace.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                bar.wheelAccum += event.angleDelta.y;
                if (Math.abs(bar.wheelAccum) >= 120) {
                    bar.stepWorkspace(bar.wheelAccum > 0 ? -1 : 1);
                    bar.wheelAccum = 0;
                }
            }
        }

        RowLayout {
            id: leftRow
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10

            SkewPanel {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 24
                skew: -6
                strokeWidth: 0
                fill: launchArea.containsMouse ? Theme.accent : Theme.surface

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"
                    color: launchArea.containsMouse ? Theme.accentText : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                MouseArea {
                    id: launchArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: bar.launcherClicked()
                }
            }

            RowLayout {
                spacing: 6

                Repeater {
                    model: 9

                    SkewPanel {
                        id: ws
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool focused: Hyprland.focusedWorkspace?.id === wsId
                        readonly property bool occupied: Hyprland.workspaces.values.some(w => w.id === wsId)
                        readonly property bool ghost: !focused && !occupied && wsId === bar.lastUsedWs + 1
                        readonly property bool shown: focused || occupied || ghost

                        // Fade/slide workspaces in and out instead of popping.
                        Layout.preferredWidth: shown ? (focused ? 36 : 28) : 0
                        Layout.preferredHeight: 24
                        opacity: shown ? (ghost ? 0.45 : 1) : 0
                        visible: opacity > 0.01
                        skew: -6
                        strokeWidth: 0
                        fill: focused ? Theme.accent : Theme.surface

                        Behavior on Layout.preferredWidth { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on opacity { NumberAnimation { duration: 220 } }

                        Text {
                            anchors.centerIn: parent
                            text: ws.wsId
                            color: ws.focused ? Theme.accentText : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: ws.focused
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: bar.gotoWorkspace(ws.wsId)
                        }
                    }
                }
            }
        }
    }

    // =========================================================== CENTRE: the island
    SkewPanel {
        id: island
        glass: true
        opacity: Math.min(1, bar.introC * 1.5)
        transform: Translate { y: (1 - bar.introC) * -70 }
        skewL: -shapeSkew   // both slants: "\\" on the left edge, "/" on the right (wider at the top)
        skewR: shapeSkew
        radiusB: shapeRB
        property real shapeSkew: bar.faceKey !== "" ? 0 : bar.skew
        Behavior on shapeSkew { SpringAnimation { spring: 5.2; damping: 0.58; epsilon: 0.05 } }
        property real shapeRB: bar.faceKey !== "" ? 28 : 0
        Behavior on shapeRB { SpringAnimation { spring: 3.6; damping: 0.4; epsilon: 0.1 } }
        y: bar.gap
        x: Math.round((bar.width - width) / 2)
        // Size: the resting content's width (with a floor), or the face asked for. Content is tied to the shape's real,
        // animated size: it shows only once the shape has ARRIVED (`fit`), so nothing appears before there is room.
        clip: true
        readonly property real restW: bar.layoutView === "notif" ? 600
             : bar.layoutView === "osd" ? 250
             : Math.max(140, (bar.layoutView === "media" ? mediaView.implicitWidth : titleView.implicitWidth) + 36)
        readonly property real targetW: bar.faceKey !== "" ? bar.faceW : restW
        readonly property real targetH: bar.faceKey !== "" ? bar.faceH : bar.pillHeight
        width: targetW
        height: targetH
        function near(v, tgt) { return Math.max(0, Math.min(1, 1 - (Math.abs(v - tgt) / Math.max(tgt, 60) - 0.04) / 0.08)); }
        readonly property real closeness: Math.min(near(width, targetW), near(height, targetH))
        property bool arrived: true            // latched: springs overshoot, and the content must not flicker out
        property real lastW: 0
        property real lastH: 0
        // Lyric lines and window names change often: the shape just follows the new width and the words swap
        // in place (see titleSlot). Hiding the text until the shape "arrives" is for real changes of content only.
        readonly property bool lyricFlow: bar.faceKey === "" && bar.layoutView === "title" && bar.view === "title"
        onTargetWChanged: if (Math.abs(targetW - lastW) > 3) { lastW = targetW; if (!lyricFlow) arrived = false; }
        onTargetHChanged: if (Math.abs(targetH - lastH) > 3) { lastH = targetH; arrived = false; }
        onClosenessChanged: if (closeness >= 0.96) arrived = true
        readonly property real fit: arrived ? 1 : closeness
        // Outline gauge: notification countdown / volume & brightness level.
        progress: bar.view === "notif" ? bar.notifProgress : (bar.view === "osd" ? bar.osdValue : -1)
        gaugeFromTop: bar.view === "notif"   // countdown: the bottom disappears first, the rest retreats to the top
        // lightning: the notification countdown is a live current (pronounced), the volume/brightness gauge a lighter
        // one; while music plays a faint current runs along the bottom edge and jumps with the bass
        gaugeSpark: !Theme.lightning ? 0 : (bar.view === "notif" ? 0.3 : (bar.view === "osd" ? 0.24 : 0))
        // the island's whole outline is lightning; while music plays it surges with the bass
        outlineSpark: Theme.lightning ? ((bar.mediaMode && bar.faceKey === "" && bar.view !== "notif")
                      ? 0.16 + 0.24 * Math.min(1, (Audio.bars[1] ?? 0) / 100) : (bar.faceKey !== "" ? 0.3 : 0.18)) : 0
        Connections {
            target: bar
            function onViewChanged() { if (bar.view === "notif") island.sparkBurst(0.3); }
        }
        progressColor: bar.view === "notif" && bar.notifCritical ? Theme.warn
                     : (bar.view === "osd" && bar.osdMuted ? Theme.fgDim : Theme.accent)
        Behavior on progress { enabled: bar.view === "osd"; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        stroke: bar.notifMode && bar.notifCritical ? Theme.warn : Theme.accentContainer
        // a tight spring: arrives fast, barely overshoots (the content waits for it, see `fit`)
        Behavior on width { SpringAnimation { spring: 5.2; damping: 0.58; epsilon: 0.25 } }
        // a looser spring for the height: it follows the width and overshoots a little, so the shape opens, not inflates
        Behavior on height { SpringAnimation { spring: 3.1; damping: 0.34; epsilon: 0.25 } }

        HoverHandler { id: islandHover; onHoveredChanged: if (hovered) bar.faceEverHovered = true }

        // Notification: click runs its default action, right-click dismisses.
        // Otherwise, while lyrics are showing, a click switches between the lyrics and the window name.
        MouseArea {
            anchors.fill: parent
            enabled: bar.notifMode || (bar.mediaMode && Lyrics.hasLyrics)
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (bar.notifMode) {
                    if (mouse.button === Qt.RightButton) Notifs.next();
                    else Notifs.activate();
                } else {
                    bar.preferTitle = !bar.preferTitle;
                    bar.titleFlash = false;
                }
            }
        }

        // swallow clicks inside the shape while a face is open (so the launcher's click-outside-to-close ignores them)
        MouseArea { anchors.fill: parent; enabled: bar.faceKey !== ""; acceptedButtons: Qt.AllButtons; hoverEnabled: false }

        // ---- faces: the shape grows to fit the dashboard ----
        DashboardFace {
            id: faceDash
            width: faceW
            height: faceH
            anchors.horizontalCenter: parent.horizontalCenter
            active: bar.shownFace === "dashboard"
            visible: bar.shownFace === "dashboard" && opacity > 0.01
            opacity: bar.faceContentOpacity
            scale: 0.90 + 0.10 * opacity
            transformOrigin: Item.Top
            transform: Translate { y: (1 - faceDash.opacity) * -14 }
        }

        // ---- Notification view ----
        RowLayout {
            id: notifView
            anchors.centerIn: parent
            spacing: 12
            opacity: (bar.notifMode && bar.restVisible) ? island.fit : 0
            visible: opacity > 0.01
            // content leaves in half the time it takes to arrive, and rises into place (like a lyric line)
            Behavior on opacity { NumberAnimation { duration: (bar.notifMode) ? 210 : 110 } }
            transform: Translate { y: (1 - notifView.opacity) * 10 }

            IconImage {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                implicitSize: 24
                source: {
                    const n = bar.shownNotif;
                    if (!n) return "";
                    if (n.image) return n.image;
                    return Quickshell.iconPath(n.appIcon, "dialog-information");
                }
            }

            RowLayout {
                Layout.preferredWidth: 500
                spacing: 10

                Text {
                    Layout.maximumWidth: 220
                    text: bar.shownNotif ? (bar.shownNotif.summary || bar.shownNotif.appName) : ""
                    color: bar.notifCritical ? Theme.warn : Theme.fg
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: bar.notifHasBody
                    text: bar.shownNotif ? bar.shownNotif.body.replace(/\s*\n\s*/g, " ") : ""
                    color: Theme.fgDim
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true; visible: !bar.notifHasBody }
            }
        }

        // ---- Volume / brightness view ----
        RowLayout {
            id: osdView
            anchors.centerIn: parent
            spacing: 12
            opacity: (bar.layoutView === "osd" && bar.restVisible) ? island.fit : 0
            visible: opacity > 0.01
            // content leaves in half the time it takes to arrive, and rises into place (like a lyric line)
            Behavior on opacity { NumberAnimation { duration: (bar.layoutView === "osd") ? 210 : 110 } }
            transform: Translate { y: (1 - osdView.opacity) * 10 }

            Text {
                text: bar.osdKind === "brightness" ? "󰃠" : (bar.osdMuted ? "󰝟" : "󰕾")
                color: bar.osdMuted ? Theme.fgDim : Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 4
            }
            Text {
                text: bar.osdKind === "brightness" ? "Brightness" : (bar.osdMuted ? "Muted" : "Volume")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
            Text {
                text: Math.round(bar.osdValue * 100) + "%"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                Layout.minimumWidth: 36
                horizontalAlignment: Text.AlignRight
            }
        }

        // ---- Window title view ----
        RowLayout {
            id: titleView
            anchors.centerIn: parent
            spacing: 10
            opacity: (bar.layoutView === "title" && bar.restVisible) ? island.fit : 0
            visible: opacity > 0.01
            // content leaves in half the time it takes to arrive, and rises into place (like a lyric line)
            Behavior on opacity { NumberAnimation { duration: (bar.layoutView === "title") ? 210 : 110 } }
            transform: Translate { y: (1 - titleView.opacity) * 10 }

            // Small visualizer icon while music plays.
            Row {
                visible: bar.mediaMode
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                height: 18

                Repeater {
                    model: 6

                    Rectangle {
                        required property int index
                        readonly property real level: (Audio.bars[index * 2 + 1] ?? 0) / 100
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(3, level * 18)
                        radius: 1.5
                        color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 8))
                        }
                }
            }

            // The window title, or (while synced lyrics are available) the line being sung, which slides up
            // into place each time the line changes.
            Item {
                id: titleSlot
                // exactly as wide as the text (no animation of its own: the island's spring is the only thing
                // that moves, so the line always sits dead centre and the island opens evenly around it)
                Layout.maximumWidth: 480
                Layout.preferredWidth: Math.min(480, Math.ceil(titleText.implicitWidth))
                Layout.preferredHeight: titleText.implicitHeight

                // the line that was just sung: lifts up and fades while the new one rises into its place
                Text {
                    id: ghost
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(480, implicitWidth)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.StyledText
                    color: Theme.fgDim
                    opacity: 0
                    font: titleText.font
                    ParallelAnimation {
                        id: ghostOut
                        NumberAnimation { target: ghost; property: "y"; from: 0; to: -10; duration: 130; easing.type: Easing.InCubic }
                        NumberAnimation { target: ghost; property: "opacity"; from: 0.7; to: 0; duration: 110 }
                    }
                }

                Text {
                    id: titleText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    readonly property string value: ToplevelManager.activeToplevel?.title ?? ""
                    // Lyrics show while music plays, except while the window name is wanted: it flashes in for a
                    // moment whenever the focused window changes, and a click on the island switches between
                    // lyrics and the window name for good.
                    readonly property bool lyric: bar.mediaMode && Lyrics.hasLyrics && !bar.preferTitle && !bar.titleFlash
                    textFormat: lyric ? Text.StyledText : Text.PlainText
                    text: lyric ? (Lyrics.line !== "" ? Lyrics.lineHtml : "♪") : (value !== "" ? value : "Desktop")
                    color: Theme.fg
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.italic: lyric
                    // When the line (not just the highlighted word) changes, the old line leaves upwards and the
                    // new one rises from below. `shownHtml` is what was on screen for the line that is ending.
                    property int seenIndex: -2
                    property string shownHtml: ""
                    // The window name swaps the same way when focus moves to another window.
                    onTextChanged: {
                        const newLine = lyric ? Lyrics.index !== seenIndex : true;
                        if (newLine) {
                            if (shownHtml !== "" && titleView.opacity > 0.5) { ghost.text = shownHtml; ghostOut.restart(); lineIn.restart(); }
                            if (lyric) seenIndex = Lyrics.index;
                        }
                        shownHtml = lyric ? titleText.text : titleText.text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                    }
                    onLyricChanged: { seenIndex = lyric ? Lyrics.index : -2; ghostOut.stop(); ghost.opacity = 0; lineIn.restart(); }
                    ParallelAnimation {
                        id: lineIn
                        NumberAnimation { target: titleText; property: "y"; from: 13; to: 0; duration: 240; easing.type: Easing.OutCubic }
                        NumberAnimation { target: titleText; property: "opacity"; from: 0; to: 1; duration: 240 }
                    }
                }
            }
        }

        // ---- Media view ----
        RowLayout {
            id: mediaView
            anchors.centerIn: parent
            spacing: 10
            opacity: (bar.layoutView === "media" && bar.restVisible) ? island.fit : 0
            visible: opacity > 0.01
            // content leaves in half the time it takes to arrive, and rises into place (like a lyric line)
            Behavior on opacity { NumberAnimation { duration: (bar.layoutView === "media") ? 210 : 110 } }
            transform: Translate { y: (1 - mediaView.opacity) * 10 }

            Text {
                text: "󰎆"
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
            }

            // Live audio visualizer.
            Row {
                id: viz
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                height: 22

                Repeater {
                    model: 16

                    Rectangle {
                        required property int index
                        readonly property real level: (Audio.bars[index] ?? 0) / 100
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(3, level * 22)
                        radius: 1.5
                        color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 20))
                        }
                }
            }

            Text {
                id: trackText
                Layout.maximumWidth: 460
                text: {
                    const p = bar.player;
                    if (!p) return "";
                    return p.trackArtist ? p.trackArtist + " – " + p.trackTitle : p.trackTitle;
                }
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            // Controls slide in on hover.
            RowLayout {
                id: controls
                readonly property bool shown: islandHover.hovered
                Layout.preferredWidth: shown ? implicitWidth : 0
                clip: true
                opacity: shown ? 1 : 0
                spacing: 12
                Behavior on Layout.preferredWidth { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 240 } }

                Repeater {
                    model: [
                        { icon: "󰒮", act: "previous" },
                        { icon: "󰏤", act: "toggle" },
                        { icon: "󰒭", act: "next" }
                    ]

                    Text {
                        id: btn
                        required property var modelData
                        text: modelData.icon
                        color: btnArea.containsMouse ? Theme.accent : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 3
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: btnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const p = bar.player;
                                if (!p) return;
                                if (btn.modelData.act === "previous") p.previous();
                                else if (btn.modelData.act === "next") p.next();
                                else p.togglePlaying();
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================== the music chip that splits off the island
    // neck: a bridge between the chip and the island that is thick while they separate and thins to nothing
    Rectangle {
        visible: bar.split > 0.02 && bar.split < 0.98
        readonly property real bridge: Math.sin(Math.PI * Math.min(1, bar.split))
        x: musicChip.x + musicChip.width - 4
        width: Math.max(0, island.x - x + 4)
        height: bar.pillHeight * 0.62 * bridge
        y: bar.gap + (bar.pillHeight - height) / 2
        color: Theme.bg
        border.color: Theme.accentContainer
        border.width: 1
        radius: height / 2
    }
    SkewPanel {
        id: musicChip
        glass: true
        outlineSpark: Theme.lightning ? 0.12 : 0
        skewL: -bar.skew
        skewR: bar.skew
        visible: bar.split > 0.01
        y: bar.gap
        height: bar.pillHeight
        width: 30 + 6 * 8
        // slides out of the island's left edge
        x: island.x + (island.width - width) / 2 - bar.split * (island.width / 2 + width / 2 + 14)
        opacity: Math.min(1, bar.split * 1.6)
        scale: 0.6 + 0.4 * Math.min(1, bar.split)
        stroke: Theme.accentContainer

        Row {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    readonly property real level: (Audio.bars[index * 2 + 1] ?? 0) / 100
                    anchors.verticalCenter: parent.verticalCenter
                    width: 4
                    height: Math.max(4, level * 22)
                    radius: 2
                    color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 8))
                }
            }
        }
    }

    // =========================================================== RIGHT: tray, volume, battery, clock
    SkewPanel {
        id: rightPill
        glass: true
        Binding { target: Theme; property: "barAnchorX"; value: rightPill.x }
        Binding { target: Theme; property: "barAnchorY"; value: rightPill.y + rightPill.height }
        outlineSpark: Theme.lightning ? 0.12 : 0
        opacity: Math.min(1, bar.introR * 1.5)
        transform: Translate { y: (1 - bar.introR) * -70 }
        y: bar.gap                            // floats level with the island; only the outer side touches the screen edge
        height: bar.pillHeight
        skewL: bar.skew                        // inner edge leans "/"
        skewR: 0                               // outer edge is straight (it is the screen edge)
        strokeRight: false
        x: bar.width - width
        width: rightRow.implicitWidth + bar.skew + 28
        Behavior on width { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }

        RowLayout {
            id: rightRow
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 14

            // ---- System tray ----
            RowLayout {
                id: tray
                visible: SystemTray.items.values.length > 0
                spacing: 10

                Repeater {
                    model: SystemTray.items

                    Item {
                        id: trayItem
                        required property SystemTrayItem modelData
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20

                        IconImage {
                            anchors.fill: parent
                            implicitSize: 20
                            source: trayItem.modelData.icon
                            opacity: trayArea.containsMouse ? 1 : 0.85
                            scale: trayArea.containsMouse ? 1.12 : 1
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }

                        QsMenuAnchor {
                            id: menuAnchor
                            menu: trayItem.modelData.menu
                            anchor.window: bar
                            anchor.rect.x: trayItem.mapToItem(null, 0, 0).x
                            anchor.rect.y: rightPill.y + rightPill.height + 4
                            anchor.rect.width: trayItem.width
                            anchor.rect.height: 1
                        }

                        MouseArea {
                            id: trayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton && !trayItem.modelData.onlyMenu)
                                    trayItem.modelData.activate();
                                else if (mouse.button === Qt.MiddleButton)
                                    trayItem.modelData.secondaryActivate();
                                else if (trayItem.modelData.hasMenu)
                                    menuAnchor.open();
                            }
                        }
                    }
                }
            }

            // ---- Connectivity (click for Wi-Fi & Bluetooth constellation) ----
            Text {
                text: "󰤨"
                color: netArea.containsMouse ? Theme.accent : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: netArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.connectivityClicked()
                }
            }

            // ---- Volume: scroll to change, click to mute ----
            Text {
                visible: bar.sink !== null && bar.sink.audio !== null
                text: {
                    const a = bar.sink?.audio;
                    if (!a) return "";
                    return (a.muted ? "󰝟 " : "󰕾 ") + Math.round(a.volume * 100) + "%";
                }
                color: bar.sink?.audio?.muted ? Theme.fgDim : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize

                MouseArea {
                    anchors.fill: parent
                    onClicked: if (bar.sink?.audio) bar.sink.audio.muted = !bar.sink.audio.muted
                    onWheel: wheel => {
                        const a = bar.sink?.audio;
                        if (!a) return;
                        const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                        a.volume = Math.max(0, Math.min(1, a.volume + step));
                    }
                }
            }

            // ---- Battery (only if one is present) ----
            Text {
                readonly property var dev: UPower.displayDevice
                visible: dev !== null && dev.isPresent && dev.isLaptopBattery
                text: {
                    if (!dev) return "";
                    const charging = dev.state === UPowerDeviceState.Charging;
                    return (charging ? "󰂄 " : "󰁹 ") + Math.round(dev.percentage * 100) + "%";
                }
                color: dev && dev.percentage < 0.2 && dev.state !== UPowerDeviceState.Charging ? Theme.warn : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            // ---- Clock ----
            Text {
                text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: bar.dashboardClicked()
                }
            }
        }
    }
}
