import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

// Desktop pet. It lives on the DESKTOP (it sits in the desktop layer, so windows cover it), wanders along the
// bottom, sits, blinks, and hops to the bass of whatever music is playing. Click it and a banded colour wipe
// sweeps the screen; underneath it the pet turns into the runner of a dino-style game on a strip along the bottom:
// click or Space/Up to jump the shards coming at you. When you crash (or press Esc) another wipe takes you back.
//   ipc call pet on|off        show / hide the pet
//   ipc call pet game on|off   start / stop the game          ipc call pet auto on|off   let a bot play it
Item {
    id: win

    property bool petOn: true
    property bool game: false
    property bool auto: false

    height: 170
    visible: petOn || game

    readonly property real floorY: height - 8
    readonly property real runnerX: 150

    // only the pet (or the whole strip while the game runs) takes the pointer (the desktop layer masks with this)
    property alias hitItem: hit
    Item {
        id: hit
        x: win.game ? 0 : critter.x - 12
        y: win.game ? 0 : critter.y - 12
        width: win.game ? win.width : critter.width + 24
        height: win.game ? win.height : critter.height + 24
    }

    // =============================================================== the creature
    property real px: 400                 // x of the creature
    property int facing: 1                // 1 right, -1 left
    property string mood: "idle"          // idle | walk | sit
    property real legPhase: 0
    property real jump: 0                 // vertical offset while hopping or jumping (negative = up)
    property bool blink: false
    property real tailAngle: 0
    readonly property bool moving: mood === "walk" || game
    SequentialAnimation {
        running: win.moving && win.visible
        loops: Animation.Infinite
        NumberAnimation { target: win; property: "tailAngle"; to: -22; duration: 160; easing.type: Easing.InOutSine }
        NumberAnimation { target: win; property: "tailAngle"; to: 22; duration: 160; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) win.tailAngle = 0
    }
    SequentialAnimation {
        id: idleWag
        loops: 2
        NumberAnimation { target: win; property: "tailAngle"; to: -22; duration: 260; easing.type: Easing.InOutSine }
        NumberAnimation { target: win; property: "tailAngle"; to: 22; duration: 260; easing.type: Easing.InOutSine }
        onFinished: win.tailAngle = 0
    }
    Timer { interval: 4200; repeat: true; running: win.petOn && !win.moving; onTriggered: idleWag.restart() }

    Item {
        id: critter
        width: 56
        height: 48
        x: win.px
        y: win.floorY - height + win.jump
        scale: 1
        transformOrigin: Item.Bottom

        // everything flips with the direction
        Item {
            anchors.fill: parent
            transform: Scale { origin.x: 28; xScale: win.facing }

            // tail (wags fast while moving, and now and then while idle; otherwise nothing animates)
            Rectangle {
                x: -2; y: 26; width: 14; height: 5; radius: 2.5
                color: Theme.accent
                transformOrigin: Item.Right
                rotation: win.tailAngle
            }
            // legs
            Rectangle {
                x: 14; width: 9; height: 8; radius: 3
                y: 41 + (win.mood === "walk" || win.game ? Math.max(0, Math.sin(win.legPhase) * 4) * -1 : 0)
                color: Qt.darker(Theme.accent, 1.25)
            }
            Rectangle {
                x: 34; width: 9; height: 8; radius: 3
                y: 41 + (win.mood === "walk" || win.game ? Math.max(0, Math.sin(win.legPhase + Math.PI) * 4) * -1 : 0)
                color: Qt.darker(Theme.accent, 1.25)
            }
            // body
            Rectangle {
                id: body
                x: 5; y: win.mood === "sit" ? 20 : 14
                width: 48; height: win.mood === "sit" ? 24 : 30
                radius: 15
                color: Theme.accent
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
            // ears
            Shape {
                anchors.fill: parent
                ShapePath {
                    fillColor: Theme.accent; strokeWidth: -1
                    startX: 10; startY: win.mood === "sit" ? 24 : 18
                    PathLine { x: 15; y: win.mood === "sit" ? 9 : 3 }
                    PathLine { x: 24; y: win.mood === "sit" ? 22 : 16 }
                }
                ShapePath {
                    fillColor: Theme.accent; strokeWidth: -1
                    startX: 34; startY: win.mood === "sit" ? 22 : 16
                    PathLine { x: 43; y: win.mood === "sit" ? 9 : 3 }
                    PathLine { x: 48; y: win.mood === "sit" ? 24 : 18 }
                }
            }
            // eyes
            Rectangle {
                x: 27; y: body.y + 7; width: 5; height: win.blink ? 1.5 : 8; radius: 2.5; color: Theme.bg
                Behavior on height { NumberAnimation { duration: 60 } }
            }
            Rectangle {
                x: 41; y: body.y + 7; width: 5; height: win.blink ? 1.5 : 8; radius: 2.5; color: Theme.bg
                Behavior on height { NumberAnimation { duration: 60 } }
            }
            // a cheek mark in the second palette colour
            Rectangle { x: 33; y: body.y + 17; width: 9; height: 3; radius: 1.5; color: Theme.accent2; opacity: 0.85 }
        }
    }

    // blink now and then
    Timer {
        interval: 3300
        repeat: true
        running: win.visible
        onTriggered: { win.blink = true; unblink.restart(); }
    }
    Timer { id: unblink; interval: 140; onTriggered: win.blink = false }

    // =============================================================== wandering
    property real target: 400
    Timer {
        interval: 2800
        repeat: true
        running: win.petOn && !win.game
        onTriggered: {
            const r = Math.random();
            if (r < 0.55) { win.target = 80 + Math.random() * (win.width - 220); win.mood = "walk"; win.facing = win.target > win.px ? 1 : -1; }
            else if (r < 0.85) win.mood = "sit";
            else win.mood = "idle";
        }
    }

    // one clock for walking, the legs, and the game
    FrameAnimation {
        running: win.visible && (win.game || win.mood === "walk")     // idle costs nothing
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            if (win.game) { win.legPhase += dt * 16; win.tickGame(dt); return; }
            if (win.mood === "walk") {
                win.legPhase += dt * 11;
                const d = win.target - win.px, step = 80 * dt;
                if (Math.abs(d) <= step) { win.px = win.target; win.mood = "idle"; }
                else win.px += Math.sign(d) * step;
            }
        }
    }

    // hop to the bass
    property real lastHop: 0
    Connections {
        target: Audio
        function onBarsChanged() {
            if (win.game || win.mood === "sit" || !Audio.playing) return;
            const b = ((Audio.bars[0] ?? 0) + (Audio.bars[1] ?? 0) + (Audio.bars[2] ?? 0)) / 3;
            if (b > 62 && Date.now() - win.lastHop > 300 && !hopAnim.running) { win.lastHop = Date.now(); hopAnim.restart(); }
        }
    }
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: win; property: "jump"; to: -24; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: win; property: "jump"; to: 0; duration: 140; easing.type: Easing.InQuad }
    }

    // =============================================================== the game
    property bool over: false
    property int score: 0
    property int best: 0
    property real dist: 0
    property real speed: 320
    property real vy: 0
    property real floorGrow: 0
    property real untilSpawn: 500
    ListModel { id: obstacles }

    // Going into the game and back out of it is covered by the banded wipe (ShardWipe.qml): the switch happens
    // when the bands cover the screen. If nothing answers, a timer does the switch anyway.
    property string pendingSwitch: ""
    function startGame() {
        if (game || pendingSwitch !== "") return;
        pendingSwitch = "toGame";
        wipeFallback.restart();
        Theme.wipeColors = [Theme.accentContainer, Theme.accent, Theme.accent2];
        Theme.wipeRequested();
    }
    function endGame() {
        if (!game || pendingSwitch !== "") return;
        pendingSwitch = "toPet";
        wipeFallback.restart();
        Theme.wipeColors = [Theme.accentContainer, Theme.accent, Theme.accent2];
        Theme.wipeRequested();
    }
    function finishSwitch() {
        const what = pendingSwitch;
        pendingSwitch = "";
        wipeFallback.stop();
        if (what === "toGame") enterGame();
        else if (what === "toPet") leaveGame();
    }
    Timer { id: wipeFallback; interval: 1800; onTriggered: win.finishSwitch() }
    Connections { target: Theme; function onWipeCovered() { if (win.pendingSwitch !== "") win.finishSwitch(); } }

    function enterGame() {
        hopAnim.stop(); jump = 0; vy = 0;
        obstacles.clear();
        over = false; score = 0; dist = 0; speed = 320; untilSpawn = 700;
        facing = 1; mood = "idle";
        game = true;
        morph.restart();
    }
    function leaveGame() { game = false; over = false; floorGrow = 0; obstacles.clear(); mood = "idle"; }
    SequentialAnimation {
        id: morph
        ParallelAnimation {
            NumberAnimation { target: win; property: "px"; to: win.runnerX; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: win; property: "floorGrow"; to: 1; duration: 700; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: critter; property: "scale"; to: 0.7; duration: 140 }
                NumberAnimation { target: critter; property: "scale"; to: 1.18; duration: 200; easing.type: Easing.OutBack }
                NumberAnimation { target: critter; property: "scale"; to: 1; duration: 180 }
            }
        }
    }
    Timer { id: backToPet; interval: 1600; onTriggered: { if (win.auto) win.restartGame(); else win.endGame(); } }
    function restartGame() { obstacles.clear(); over = false; score = 0; dist = 0; speed = 320; untilSpawn = 600; jump = 0; vy = 0; }

    function doJump() {
        if (!game) return;
        if (over) { backToPet.stop(); restartGame(); return; }
        if (jump >= -1) vy = -640;        // only from the ground
    }

    function tickGame(dt) {
        if (over || floorGrow < 0.9) return;
        // runner physics
        vy += 2000 * dt;
        jump += vy * dt;
        if (jump >= 0) { jump = 0; vy = 0; }
        // world
        speed = Math.min(780, speed + 7 * dt);
        dist += speed * dt;
        score = Math.floor(dist / 10);
        untilSpawn -= speed * dt;
        if (untilSpawn <= 0) {
            const tall = Math.random() < 0.4;
            obstacles.append({ ox: win.width + 40, ow: tall ? 26 : 36 + Math.random() * 22, oh: tall ? 58 : 30 + Math.random() * 14 });
            untilSpawn = 420 + Math.random() * 420 + speed * 0.28;
        }
        // move, collide, clean up
        const rx0 = runnerX + 8, rx1 = runnerX + 48, ry0 = floorY - 44 + jump + 4, ry1 = floorY + jump;
        let nextGap = 1e9;
        for (let i = obstacles.count - 1; i >= 0; i--) {
            const o = obstacles.get(i);
            const nx = o.ox - speed * dt;
            if (nx + o.ow < -20) { obstacles.remove(i); continue; }
            obstacles.setProperty(i, "ox", nx);
            if (rx1 > nx + 3 && rx0 < nx + o.ow - 3 && ry1 > floorY - o.oh + 4) { crash(); return; }
            if (nx + o.ow > rx0 && nx - rx1 < nextGap) nextGap = nx - rx1;
        }
        // the bot jumps when the next shard is about 0.24 s away
        if (auto && jump === 0 && nextGap > 0 && nextGap < speed * 0.24) vy = -640;
    }
    function crash() {
        over = true;
        best = Math.max(best, score);
        backToPet.restart();
    }

    // click the pet: start the game; in the game: jump
    MouseArea {
        anchors.fill: hit
        cursorShape: Qt.PointingHandCursor
        onPressed: { keys.forceActiveFocus(); if (win.game) win.doJump(); else if (win.pendingSwitch === "") win.startGame(); }
    }
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (!win.game) return;
            if (event.key === Qt.Key_Space || event.key === Qt.Key_Up) win.doJump();
            else if (event.key === Qt.Key_Escape) win.endGame();
            else return;
            event.accepted = true;
        }
    }

    // floor, obstacles and score
    Item {
        anchors.fill: parent
        visible: win.game
        opacity: win.floorGrow

        Rectangle {
            x: 0; y: win.floorY + 1; height: 2
            width: win.width * win.floorGrow
            color: Theme.accentContainer
        }
        Repeater {
            model: obstacles
            SkewPanel {
                required property real ox
                required property real ow
                required property real oh
                x: ox
                y: win.floorY - oh
                width: ow
                height: oh
                skew: 8
                fill: Theme.surface
                stroke: Theme.accent2
                strokeWidth: 2
            }
        }
        Text {
            anchors { right: parent.right; rightMargin: 40; top: parent.top; topMargin: 18 }
            text: String(win.score).padStart(5, "0") + "     best " + String(win.best).padStart(5, "0")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 3
            font.bold: true
            font.italic: true
        }
        Text {
            anchors.centerIn: parent
            visible: win.over
            text: "GAME OVER   " + win.score
            color: Theme.warn
            font.family: Theme.font
            font.pixelSize: 34
            font.bold: true
            font.italic: true
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
            text: "click or Space to jump  ·  Esc to quit"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.italic: true
            opacity: win.score < 30 && !win.over ? 0.8 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }
}
