import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Networking
import QtQuick
import QtQuick.Effects
import "widgets"

// Lock screen (sample, for the demo). A real Wayland session lock: your password unlocks it (PAM "login", like ii).
//   qs -p <dir> ipc call lock test   lock with a silent 2-minute failsafe (it unlocks by itself, for trying it out)
//   qs -p <dir> ipc call lock lock   lock for real (password only)
// Same family as the switcher and the Wi-Fi/BT screen: a big rolling clock in the middle, the machine's status as
// pills on an orbit joined by thin beams, and a password pill with a lightning edge. Unlocking: the pills spiral into
// the clock, the clock swells and fades, the blurred wallpaper clears, then the lock lets go.
Scope {
    id: root

    property bool locked: false
    property bool testMode: false
    property string typed: ""
    property bool busy: false
    property bool failed: false
    property real failsafeLeft: 0

    function lock(test) {
        testMode = test;
        typed = ""; failed = false; busy = false; leaving = false; leave = 0;
        failsafeLeft = 120;
        locked = true;
    }
    property bool leaving: false
    property real leave: 0
    NumberAnimation { id: leaveAnim; target: root; property: "leave"; from: 0; to: 1; duration: 650; easing.type: Easing.InCubic
        onFinished: root.locked = false }
    function unlock() { if (leaving) return; leaving = true; leaveAnim.restart(); }

    Timer {
        interval: 1000; repeat: true
        running: root.locked && root.testMode && !root.leaving
        onTriggered: { root.failsafeLeft -= 1; if (root.failsafeLeft <= 0) root.unlock(); }
    }

    PamContext {
        id: pam
        onPamMessage: { if (this.responseRequired) this.respond(root.typed); }
        onCompleted: result => {
            root.busy = false;
            if (result == PamResult.Success) root.unlock();
            else root.failed = true;      // the pill shows it, then clears the dots (see failAnim)
        }
    }
    function submit() { if (busy || typed === "") return; busy = true; failed = false; pam.start(); }

    IpcHandler {
        target: "lock"
        function test(): void { root.lock(true); }
        function lock(): void { root.lock(false); }
    }

    WlSessionLock {
        locked: root.locked

        WlSessionLockSurface {
            id: surf
            color: "black"

            readonly property real cx: width / 2
            readonly property real cy: height / 2 - 40
            property real intro: 0
            Component.onCompleted: introAnim.start()
            NumberAnimation { id: introAnim; target: surf; property: "intro"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

            // ---- background: the wallpaper, blurred and dimmed; it clears as you unlock ----
            Image {
                id: wall
                anchors.fill: parent
                source: Theme.wallpaper !== "" ? "file://" + Theme.wallpaper : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                visible: wall.status === Image.Ready
                blurEnabled: true
                blur: 1.0 - 0.8 * root.leave
                blurMax: 64
                brightness: -0.25 * (1 - root.leave)
                saturation: 0.1
            }
            Rectangle {
                anchors.fill: parent
                visible: wall.status !== Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.bg }
                    GradientStop { position: 1; color: Qt.darker(Theme.bg, 1.6) }
                }
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35 * (1 - root.leave)) }

            // ---- status orbit ----
            readonly property var sats: {
                const out = [];
                const bat = UPower.displayDevice;
                if (bat && bat.isPresent) out.push({ icon: bat.state === UPowerDeviceState.Charging ? "󰂄" : "󰁹", title: Math.round(bat.percentage * 100) + "%", sub: "battery" });
                let net = "offline";
                for (const d of Networking.devices.values) for (const n of (d.networks?.values ?? [])) if (n.connected) net = n.name;
                out.push({ icon: "󰤨", title: net, sub: "network" });
                const p = Mpris.players.values.find(x => x.isPlaying) ?? Mpris.players.values.find(x => (x.trackTitle ?? "") !== "");
                if (p) out.push({ icon: "󰎈", title: p.trackTitle || "music", sub: p.trackArtist || "now playing" });
                out.push({ icon: "󰀄", title: Quickshell.env("USER"), sub: "locked" });
                return out;
            }
            property real orbit: 0
            FrameAnimation { running: root.locked; onTriggered: surf.orbit += frameTime * 0.06 }
            function satPos(i) {
                const n = Math.max(1, sats.length);
                const a = orbit + i / n * Math.PI * 2 - Math.PI / 2 + root.leave * 2.4;
                const k = Math.max(0, surf.intro) * (1 - root.leave);
                return { x: cx + Math.cos(a) * 430 * k, y: cy + Math.sin(a) * 250 * k };
            }

            Repeater {
                model: surf.sats
                Item {
                    id: sat
                    required property var modelData
                    required property int index
                    readonly property var p: surf.satPos(index)
                    // beam to the clock
                    Rectangle {
                        readonly property real dx: sat.p.x - surf.cx
                        readonly property real dy: sat.p.y - surf.cy
                        x: surf.cx; y: surf.cy
                        width: Math.hypot(dx, dy); height: 1
                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.14)
                        transformOrigin: Item.Left
                        rotation: Math.atan2(dy, dx) * 180 / Math.PI
                        antialiasing: true
                    }
                    Rectangle {
                        x: sat.p.x - width / 2; y: sat.p.y - height / 2
                        width: 210; height: 54; radius: 27
                        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.82)
                        border.color: Qt.rgba(1, 1, 1, 0.14)
                        opacity: Math.min(1, surf.intro * 1.5) * (1 - root.leave)
                        scale: 0.6 + 0.4 * surf.intro
                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Rectangle {
                                width: 34; height: 34; radius: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                Text { anchors.centerIn: parent; text: sat.modelData.icon; color: Theme.accent; font.family: Theme.font; font.pixelSize: 17 }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text { width: 140; text: sat.modelData.title; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.bold: true }
                                Text { width: 140; text: sat.modelData.sub; elide: Text.ElideRight; color: Theme.fgDim; font.family: Theme.font; font.pixelSize: 10 }
                            }
                        }
                    }
                }
            }

            // ---- the clock ----
            SystemClock { id: clock; precision: SystemClock.Seconds }
            Item {
                id: clockBox
                x: surf.cx - width / 2
                y: surf.cy - height / 2
                width: 360; height: 200
                scale: (0.85 + 0.15 * surf.intro) * (1 + 0.35 * root.leave)
                opacity: surf.intro * (1 - root.leave)
                // halo
                Rectangle {
                    anchors.centerIn: parent
                    width: 300; height: 300; radius: 150
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.07)
                }
                RollText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 34
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Theme.fg
                    font: Qt.font({ family: Theme.font, pixelSize: 96, bold: true })
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 160
                    text: Qt.formatDateTime(clock.date, "dddd · d MMMM")
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 15
                }
            }

            // ---- password pill ----
            Item {
                id: pw
                width: 360; height: 52
                x: surf.cx - width / 2
                y: surf.cy + 330
                opacity: surf.intro * (1 - root.leave)
                property real shake: 0
                transform: Translate { x: Math.sin(pw.shake * Math.PI * 6) * 14 * (1 - pw.shake) }
                NumberAnimation { id: shakeAnim; target: pw; property: "shake"; from: 0; to: 1; duration: 480 }
                Connections { target: root; function onFailedChanged() { if (root.failed) { shakeAnim.restart(); edge.burst(0.5); } } }

                Rectangle {
                    anchors.fill: parent
                    radius: 26
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.85)
                    border.color: root.failed ? Theme.warn : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    border.width: 1
                }
                EdgeSpark {
                    id: edge
                    anchors.fill: parent
                    visible: Theme.lightning
                    // a stadium (pill) outline
                    points: {
                        const pts = [], r = 26, w = pw.width, h = pw.height;
                        for (let i = 0; i <= 10; i++) { const a = -Math.PI / 2 + Math.PI * i / 10; pts.push([w - r + Math.cos(a) * r, r + Math.sin(a) * r]); }
                        for (let i = 0; i <= 10; i++) { const a = Math.PI / 2 + Math.PI * i / 10; pts.push([r + Math.cos(a) * r, r + Math.sin(a) * r]); }
                        return pts;
                    }
                    closed: true
                    color: root.failed ? Theme.warn : Theme.accent
                    intensity: root.busy ? 0.4 : (root.typed.length > 0 ? 0.24 : 0.14)
                }
                // The typed characters as dots. Only the new dot animates: it rises in with a pop; deleting shrinks the
                // last one away; the row glides to stay centred. On Enter the dots gather into the middle while the
                // password is checked; if it is wrong they spread back out in red, the pill shakes, and they drain away.
                ListModel { id: dots }
                Connections {
                    target: root
                    function onTypedChanged() {
                        if (root.typed === "" && input.text !== "") input.text = "";
                        const n = Math.min(24, root.typed.length);
                        while (dots.count < n) { dots.append({}); edge.burst(0.12); }
                        while (dots.count > n) dots.remove(dots.count - 1);
                    }
                    function onBusyChanged() { if (root.busy) gatherIn.restart(); }
                    function onFailedChanged() { if (root.failed) failAnim.restart(); }
                }
                property real gather: 0
                NumberAnimation { id: gatherIn; target: pw; property: "gather"; to: 1; duration: 320; easing.type: Easing.InOutCubic }
                SequentialAnimation {
                    id: failAnim
                    NumberAnimation { target: pw; property: "gather"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    PauseAnimation { duration: 380 }
                    ScriptAction { script: root.typed = "" }
                }
                ListView {
                    id: dotRow
                    orientation: ListView.Horizontal
                    interactive: false
                    spacing: 9
                    model: dots
                    height: 14
                    width: Math.max(1, dots.count * 18 - 9)
                    Behavior on width { SpringAnimation { spring: 5; damping: 0.55; epsilon: 0.2 } }
                    anchors.centerIn: parent
                    delegate: Rectangle {
                        id: dot
                        required property int index
                        width: 9; height: 9; radius: 4.5
                        y: 2.5
                        color: root.failed ? Theme.warn : (pw.gather > 0.5 ? Theme.accent : Theme.fg)
                        Behavior on color { ColorAnimation { duration: 160 } }
                        // gather: every dot slides to the middle of the row
                        transform: Translate { x: (dotRow.width / 2 - (dot.x + 4.5)) * pw.gather }
                    }
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "scale"; from: 0; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                            NumberAnimation { property: "y"; from: 14; to: 2.5; duration: 220; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "scale"; to: 0; duration: 160; easing.type: Easing.InCubic }
                            NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                        }
                    }
                }
                // while checking: the gathered dots pulse as one
                Rectangle {
                    anchors.centerIn: parent
                    width: 14; height: 14; radius: 7
                    color: Theme.accent
                    visible: root.busy && pw.gather > 0.95
                    SequentialAnimation on scale {
                        running: root.busy; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 1.6; duration: 380; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.6; to: 1; duration: 380; easing.type: Easing.InCubic }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.typed.length === 0 && dots.count === 0
                    text: root.failed ? "wrong password, try again" : "type your password"
                    color: root.failed ? Theme.warn : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 13
                }
                TextInput {
                    id: input
                    width: 0; height: 0; opacity: 0
                    focus: true
                    echoMode: TextInput.Password
                    text: root.typed
                    onTextChanged: { if (root.typed !== text && !root.busy) { root.typed = text; if (text !== "") { root.failed = false; pw.gather = 0; } } }
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: { root.typed = ""; }
                    Component.onCompleted: forceActiveFocus()
                }
            }
            MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
        }
    }
}
