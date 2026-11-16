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

    readonly property int gap: 8
    readonly property int pillHeight: 40
    readonly property int smooth: 320
    readonly property int skew: 14

    anchors { top: true; left: true; right: true }
    implicitHeight: pillHeight + gap * 2
    exclusiveZone: pillHeight + gap
    color: "transparent"

    // Only the panels take input; the rest of the surface is click-through.
    mask: Region {
        regions: [
            Region { item: leftPill },
            Region { item: island },
            Region { item: rightPill }
        ]
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    Process { id: wsSwitch }
    function gotoWorkspace(n) {
        // Hyprland 0.5x uses Lua dispatchers, so go through hyprctl with the Lua form.
        wsSwitch.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + n + " })"];
        wsSwitch.running = true;
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink

    // The player that is currently playing, if any.
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    readonly property bool mediaMode: player !== null

    // Notification currently shown in the island (see Notifs.qml). `shownNotif` keeps the last
    // one around so the content can fade out instead of blanking.
    readonly property var notif: Notifs.current
    readonly property bool notifMode: notif !== null
    property var shownNotif: null
    onNotifChanged: {
        if (notif !== null) {
            shownNotif = notif;
            notifTimer.restart();
        }
    }
    readonly property bool notifHasBody: shownNotif !== null && (shownNotif.body ?? "") !== ""
    readonly property bool notifCritical: shownNotif !== null && shownNotif.urgency === NotificationUrgency.Critical

    Timer {
        id: notifTimer
        running: bar.notifMode && !islandHover.hovered
        interval: {
            const n = bar.shownNotif;
            if (!n) return 5000;
            if (n.urgency === NotificationUrgency.Critical) return 12000;
            return n.expireTimeout > 0 ? n.expireTimeout * 1000 : 5000;
        }
        onTriggered: Notifs.next()
    }

    // =========================================================== LEFT: launcher + workspaces
    SkewPanel {
        id: leftPill
        x: bar.gap
        y: bar.gap
        height: bar.pillHeight
        skew: bar.skew
        width: leftRow.implicitWidth + bar.skew + 28
        Behavior on width { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }

        RowLayout {
            id: leftRow
            anchors { left: parent.left; leftMargin: 14 + bar.skew / 2; verticalCenter: parent.verticalCenter }
            spacing: 10

            SkewPanel {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 24
                skew: 6
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
                        readonly property bool shown: focused || occupied

                        // Fade/slide workspaces in and out instead of popping.
                        Layout.preferredWidth: shown ? (focused ? 36 : 28) : 0
                        Layout.preferredHeight: 24
                        opacity: shown ? 1 : 0
                        visible: opacity > 0.01
                        skew: 6
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
        skew: bar.skew
        y: bar.gap
        x: Math.round((bar.width - width) / 2)
        // Size follows whichever view is active, with a floor so it never collapses.
        width: bar.notifMode ? 500
             : Math.max(140, (bar.mediaMode ? mediaView.implicitWidth : titleView.implicitWidth) + 36)
        height: bar.pillHeight
        stroke: bar.notifMode && bar.notifCritical ? Theme.warn : Theme.accentContainer
        Behavior on width { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }

        HoverHandler { id: islandHover }

        // Click a notification to run its default action; right-click to dismiss.
        MouseArea {
            anchors.fill: parent
            enabled: bar.notifMode
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) Notifs.next();
                else Notifs.activate();
            }
        }

        // ---- Notification view ----
        RowLayout {
            id: notifView
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
            spacing: 12
            opacity: bar.notifMode ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }

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
                Layout.preferredWidth: 400
                spacing: 10

                Text {
                    Layout.maximumWidth: 180
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

        // ---- Window title view ----
        Text {
            id: titleView
            anchors.centerIn: parent
            readonly property string value: ToplevelManager.activeToplevel?.title ?? ""
            text: value !== "" ? value : "Desktop"
            color: Theme.fg
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 420)
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            opacity: (bar.mediaMode || bar.notifMode) ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }
        }

        // ---- Media view ----
        RowLayout {
            id: mediaView
            anchors.centerIn: parent
            spacing: 10
            opacity: bar.mediaMode && !bar.notifMode ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: 240 } }

            Text {
                text: "󰎆"
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 3
            }

            Text {
                id: trackText
                Layout.maximumWidth: 360
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

    // =========================================================== RIGHT: tray, volume, battery, clock
    SkewPanel {
        id: rightPill
        y: bar.gap
        height: bar.pillHeight
        skew: bar.skew
        x: bar.width - width - bar.gap
        width: rightRow.implicitWidth + bar.skew + 28
        Behavior on width { NumberAnimation { duration: bar.smooth; easing.type: Easing.OutCubic } }

        RowLayout {
            id: rightRow
            anchors { right: parent.right; rightMargin: 14 + bar.skew / 2; verticalCenter: parent.verticalCenter }
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
            }
        }
    }
}
