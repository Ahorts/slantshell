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
        function isLocked(): bool { return root.locked; }
        // ends a TEST lock early (for previews); does nothing to a real lock
        function release(): void { if (root.testMode) root.unlock(); }
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


            // ---- the flow layer: energy moving between the core (the clock), the status pills and the password pill ----
            // Like the Wi-Fi/Bluetooth screen's beams, taken further: curved glowing beams with travelling pulses, a ring
            // of ticks round the core with the seconds sweeping, a charge ring that fills as you type, a beam down to the
            // password pill that fires a spark up into the core on every key, streams while the password is checked
            // (and the status beams flow inwards), and kicks red sparks back down when it's wrong. Faint motes drift up.
            property var shots: []                   // sparks on the password beam: { t0, dir: 1 up / -1 down, warn }
            property real charge: Math.min(1, root.typed.length / 10)
            Behavior on charge { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            readonly property var motes: {
                const out = [];
                for (let i = 0; i < 48; i++) out.push({ x: Math.random(), y: Math.random(), v: 0.012 + Math.random() * 0.03, r: 0.6 + Math.random() * 1.6, ph: Math.random() * 6.28 });
                return out;
            }
            Connections {
                target: root
                property int lastLen: 0
                function onTypedChanged() {
                    if (root.typed.length > lastLen) surf.shots = surf.shots.concat([{ t0: surf.t, dir: 1, warn: false }]);
                    lastLen = root.typed.length;
                }
                function onFailedChanged() {
                    if (root.failed) surf.shots = surf.shots.concat([0, 0.09, 0.18].map(d => ({ t0: surf.t + d, dir: -1, warn: true })));
                }
            }
            Canvas {
                id: flow
                anchors.fill: parent
                renderTarget: Canvas.FramebufferObject
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const k = surf.intro * (1 - root.leave);
                    if (k <= 0.01) return;
                    const cx = surf.cx, cy = surf.cy, t = surf.t, R = 150;
                    const ac = Theme.accent, wc = Theme.warn, fg = Theme.fg;
                    const col = root.failed ? wc : ac;
                    const rgba = (c, a) => Qt.rgba(c.r, c.g, c.b, a * k);

                    // motes, drifting up
                    for (const m of surf.motes) {
                        const y = ((m.y - t * m.v) % 1 + 1) % 1 * height;
                        const x = m.x * width + Math.sin(t * 0.4 + m.ph) * 14;
                        ctx.beginPath(); ctx.arc(x, y, m.r, 0, Math.PI * 2);
                        ctx.fillStyle = rgba(fg, 0.10 + 0.08 * Math.sin(t + m.ph)); ctx.fill();
                    }

                    // orbit tracks (the status pills ride the inner one), the outer one dashed and drifting
                    ctx.lineWidth = 1;
                    ctx.beginPath(); ctx.ellipse(cx - 430, cy - 250, 860, 500); ctx.strokeStyle = rgba(ac, 0.10); ctx.stroke();
                    ctx.setLineDash([3, 9]); ctx.lineDashOffset = -t * 6;
                    ctx.beginPath(); ctx.ellipse(cx - 480, cy - 290, 960, 580); ctx.strokeStyle = rgba(ac, 0.07); ctx.stroke();
                    ctx.setLineDash([]);

                    // keystroke sparks that have reached the core make it flash
                    let hit = 0;
                    const live = [];
                    for (const s of surf.shots) {
                        const age = t - s.t0;
                        if (age < 1.2) live.push(s);
                        if (s.dir > 0 && age > 0.42) hit += Math.exp(-(age - 0.42) * 7);
                    }
                    if (live.length !== surf.shots.length) surf.shots = live;
                    hit = Math.min(1, hit);

                    // core ring: 60 ticks turning slowly, the seconds sweeping, the charge ring inside
                    const sec = (new Date()).getSeconds() + (new Date()).getMilliseconds() / 1000;
                    for (let i = 0; i < 60; i++) {
                        const a = i / 60 * Math.PI * 2 + t * 0.05;
                        const major = i % 5 === 0;
                        const r1 = R + 8, r2 = R + (major ? 18 : 13);
                        ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
                        ctx.strokeStyle = rgba(fg, major ? 0.30 : 0.13); ctx.lineWidth = major ? 1.6 : 1; ctx.stroke();
                    }
                    const sa = -Math.PI / 2, se = sa + sec / 60 * Math.PI * 2;
                    ctx.beginPath(); ctx.arc(cx, cy, R, sa, se); ctx.strokeStyle = rgba(ac, 0.55 + 0.4 * hit); ctx.lineWidth = 2.2; ctx.lineCap = "round"; ctx.stroke();
                    ctx.beginPath(); ctx.arc(cx + Math.cos(se) * R, cy + Math.sin(se) * R, 3.6, 0, Math.PI * 2); ctx.fillStyle = rgba(fg, 0.95); ctx.fill();
                    ctx.beginPath(); ctx.arc(cx + Math.cos(se) * R, cy + Math.sin(se) * R, 9, 0, Math.PI * 2); ctx.fillStyle = rgba(ac, 0.25); ctx.fill();
                    if (surf.charge > 0.001 || root.busy) {
                        const ch = root.busy ? 1 : surf.charge;
                        ctx.beginPath(); ctx.arc(cx, cy, R - 12, sa, sa + ch * Math.PI * 2);
                        ctx.strokeStyle = rgba(col, root.busy ? 0.5 + 0.35 * Math.sin(t * 9) : 0.6); ctx.lineWidth = 3; ctx.stroke();
                    }
                    if (hit > 0.02) {     // flash ripple
                        ctx.beginPath(); ctx.arc(cx, cy, R + 24 + (1 - hit) * 40, 0, Math.PI * 2);
                        ctx.strokeStyle = rgba(ac, 0.35 * hit); ctx.lineWidth = 2; ctx.stroke();
                    }

                    // beams to the status pills: curved, glowing, with two pulses each (inwards while checking)
                    const n = surf.sats.length;
                    for (let i = 0; i < n; i++) {
                        const p = surf.satPos(i);
                        const dx = p.x - cx, dy = p.y - cy, d = Math.hypot(dx, dy);
                        if (d < R + 60) continue;
                        const ux = dx / d, uy = dy / d, nx = -uy, ny = ux;
                        const sx = cx + ux * (R + 22), sy = cy + uy * (R + 22);
                        const cut = Math.abs(ux) * 108 + Math.abs(uy) * 30;
                        const ex = p.x - ux * cut, ey = p.y - uy * cut;
                        const bow = 26 * Math.sin(t * 0.7 + i * 1.7);
                        const qx = (sx + ex) / 2 + nx * bow, qy = (sy + ey) / 2 + ny * bow;
                        const g = ctx.createLinearGradient(sx, sy, ex, ey);
                        g.addColorStop(0, rgba(ac, 0.55)); g.addColorStop(0.5, rgba(ac, 0.16)); g.addColorStop(1, rgba(ac, 0.45));
                        ctx.beginPath(); ctx.moveTo(sx, sy); ctx.quadraticCurveTo(qx, qy, ex, ey);
                        ctx.strokeStyle = g; ctx.lineWidth = 1.5; ctx.lineCap = "round"; ctx.stroke();
                        for (let j = 0; j < 2; j++) {
                            let u = (t * (root.busy ? 1.6 : 0.42) + i * 0.27 + j * 0.5) % 1;
                            if (root.busy) u = 1 - u;
                            const a1 = (1 - u) * (1 - u), a2 = 2 * (1 - u) * u, a3 = u * u;
                            const px = a1 * sx + a2 * qx + a3 * ex, py = a1 * sy + a2 * qy + a3 * ey;
                            const fade = Math.sin(u * Math.PI);
                            ctx.beginPath(); ctx.arc(px, py, 7, 0, Math.PI * 2); ctx.fillStyle = rgba(ac, 0.18 * fade); ctx.fill();
                            ctx.beginPath(); ctx.arc(px, py, 2.4, 0, Math.PI * 2); ctx.fillStyle = rgba(fg, 0.85 * fade); ctx.fill();
                        }
                    }

                    // the beam down to the password pill, its sparks, and the stream while checking
                    const bx = cx, by0 = cy + R + 24, by1 = cy + 330 - 8;
                    const wob = root.busy ? 3 : 0;
                    ctx.beginPath();
                    for (let s2 = 0; s2 <= 20; s2++) {
                        const u = s2 / 20, y = by0 + (by1 - by0) * u, x = bx + Math.sin(u * 14 - t * 12) * wob * Math.sin(u * Math.PI);
                        if (s2 === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    const gb = ctx.createLinearGradient(bx, by0, bx, by1);
                    gb.addColorStop(0, rgba(col, 0.5)); gb.addColorStop(1, rgba(col, root.typed.length > 0 || root.busy ? 0.6 : 0.2));
                    ctx.strokeStyle = gb; ctx.lineWidth = root.busy ? 2 : 1.4; ctx.stroke();
                    const spark = (u, c, big) => {
                        const y = by1 + (by0 - by1) * u;
                        ctx.beginPath(); ctx.arc(bx, y, big ? 10 : 7, 0, Math.PI * 2); ctx.fillStyle = rgba(c, 0.25); ctx.fill();
                        ctx.beginPath(); ctx.arc(bx, y, big ? 3.4 : 2.6, 0, Math.PI * 2); ctx.fillStyle = rgba(fg, 0.95); ctx.fill();
                    };
                    for (const s of live) {
                        const age = t - s.t0;
                        if (age < 0 || age > 0.42) continue;
                        const u = age / 0.42;
                        spark(s.dir > 0 ? u * u * (3 - 2 * u) : 1 - u, s.warn ? wc : ac, true);
                    }
                    if (root.busy) for (let j = 0; j < 4; j++) spark((t * 2.2 + j / 4) % 1, ac, false);
                }
            }

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
            property real t: 0                       // seconds since the lock came up (drives the flow layer)
            FrameAnimation {
                running: root.locked
                onTriggered: { surf.orbit += frameTime * 0.06; surf.t += frameTime; flow.requestPaint(); }
            }
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
