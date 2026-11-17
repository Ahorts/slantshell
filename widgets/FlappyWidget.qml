import QtQuick
import QtQuick.Shapes
import ".."

// Flappy, living on the desktop. No card, no box: a little bird sits on a thin wire that comes in from the right
// edge of the screen. Click it (then Space / Up / click to flap) and it simply hops off the wire and flies left;
// slanted glass shards drift in from the left out of nothing (they fade in at the edge) and the score glows faintly
// behind. Crash: the bird tumbles, the shards slide on and fade away, and the bird flies back to its wire.
// At rest nothing animates except an occasional blink (the desktop layer stays idle).
// `auto` (ipc call flappy on) lets it play itself.
Item {
    id: game

    // ---- field ----
    readonly property real areaW: 860
    readonly property real areaH: 380
    // The wire hangs from the right bar's front corner (Theme.barAnchorX/Y, screen coordinates) to past the screen's
    // right edge, sagging in between; the bird perches at the lowest point. This item sits at the screen's right
    // edge, 60 px from the top (see Background.qml).
    readonly property real offX: parent ? parent.width - areaW : 0
    readonly property real ax: (Theme.barAnchorX >= 0 ? Theme.barAnchorX - offX : areaW - 420) + 3
    readonly property real ay: Theme.barAnchorY - 60 - 1
    readonly property real bx: areaW + 30
    readonly property real by: ay + 4
    readonly property real sag: 74
    readonly property real wireY: (ay + by) / 2 + sag
    readonly property real perchX: (ax + bx) / 2
    readonly property real birdX: perchX               // the bird stays in this column while playing
    readonly property real birdR: 11
    readonly property real gravity: 980
    readonly property real flapSpeed: -330
    readonly property real pipeSpeed: 135
    readonly property real pipeW: 44
    readonly property real gapH: 118
    readonly property real spacing: 230
    readonly property real fadeEdge: 140                // shards fade in over this many px at the left edge

    width: areaW
    height: areaH

    // ---- state ----
    property bool auto: false
    property string phase: "perched"                   // perched | playing | falling | returning
    property int score: 0
    property int best: 0
    property real birdY: wireY - birdR
    property real birdXo: 0                            // offset from birdX (only while returning)
    property real vy: 0
    property real tilt: 0
    property var pipes: []                              // [{ x, gapY, scored }]
    property real pipesAlpha: 1                         // whole-field fade (after a crash)
    readonly property bool active: phase !== "perched"

    function randomGap() {
        const top = 40 + gapH / 2, bottom = areaH - 40 - gapH / 2;
        return top + Math.random() * (bottom - top);
    }
    function start() {
        score = 0;
        const ps = [];
        for (let i = 0; i < 4; i++) ps.push({ x: -pipeW - i * spacing - 60, gapY: randomGap(), scored: false });
        pipes = ps;
        pipesAlpha = 1;
        phase = "playing";
        vy = flapSpeed;                                 // the hop off the wire
    }
    function flap() {
        if (phase === "perched") start();
        else if (phase === "playing") vy = flapSpeed;
    }
    function crash() {
        if (phase !== "playing") return;
        best = Math.max(best, score);
        phase = "falling";
    }

    // autopilot: aim a little below the middle of the next gap
    function botThink() {
        let next = null;
        for (const p of pipes) if (p.x <= birdX + birdR && p.x + pipeW >= birdX - birdR - 140 && (next === null || p.x > next.x)) next = p;
        if (next === null) for (const p of pipes) if (p.x < birdX && (next === null || p.x > next.x)) next = p;
        const target = next ? next.gapY + 16 : areaH / 2;
        if (birdY > target && vy > -120) vy = flapSpeed;
    }

    function step(dt) {
        if (phase === "playing" || phase === "falling") {
            if (phase === "playing" && auto) botThink();
            vy += gravity * dt;
            birdY += vy * dt;
            tilt = phase === "falling" ? Math.min(160, tilt + 420 * dt) : Math.max(-25, Math.min(70, vy * 0.12));
        }
        // shards keep sliding right (also after a crash, while they fade out)
        const ps = pipes;
        let maxSpacingX = Infinity;
        for (const p of ps) maxSpacingX = Math.min(maxSpacingX, p.x);
        for (const p of ps) {
            p.x += pipeSpeed * dt;
            if (phase === "playing") {
                if (p.x > areaW + 20) { p.x = maxSpacingX - spacing; p.gapY = randomGap(); p.scored = false; }
                if (!p.scored && p.x > birdX + birdR) { p.scored = true; score += 1; }
                if (birdX + birdR > p.x && birdX - birdR < p.x + pipeW
                    && (birdY - birdR < p.gapY - gapH / 2 || birdY + birdR > p.gapY + gapH / 2)) crash();
            }
        }
        pipes = ps.map(q => ({ x: q.x, gapY: q.gapY, scored: q.scored }));   // fresh objects, so the shards' bindings see the move
        if (phase === "playing") {
            if (birdY - birdR < 0) { birdY = birdR; vy = 0; }
            if (birdY + birdR > areaH) crash();
        }
        if (phase === "falling") {
            pipesAlpha = Math.max(0, pipesAlpha - dt * 1.6);
            if (birdY > areaH + 30) flyHome();
        }
    }
    FrameAnimation {
        running: game.phase === "playing" || game.phase === "falling"
        onTriggered: game.step(Math.min(frameTime, 0.05))
    }

    // after a crash: the bird reappears from below the right edge and flies back up to its wire in an arc
    function flyHome() {
        phase = "returning";
        pipes = [];
        homeAnim.restart();
    }
    property real home: 0
    SequentialAnimation {
        id: homeAnim
        ScriptAction { script: { game.tilt = -20; } }
        NumberAnimation { target: game; property: "home"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
        ScriptAction { script: { game.phase = "perched"; game.tilt = 0; game.birdY = game.wireY - game.birdR; game.birdXo = 0; } }
    }
    onHomeChanged: if (phase === "returning") {
        const t = home;
        birdXo = (1 - t) * 120 * Math.sin(Math.PI * t * 0.5 + Math.PI / 2);
        birdY = (areaH + 40) + ((wireY - birdR) - (areaH + 40)) * t - Math.sin(Math.PI * t) * 60;
        tilt = -20 * (1 - t);
    }

    // autopilot starts games on its own
    Timer { running: game.auto && game.phase === "perched"; interval: 900; onTriggered: game.flap() }

    // ---- input ----
    focus: true
    Keys.onSpacePressed: flap()
    Keys.onUpPressed: flap()
    // what takes the pointer: the bird on its wire at rest, the whole field while playing
    readonly property Item hitItem: active ? game : perchHit
    Item { id: perchHit; x: game.perchX - 40; y: game.wireY - 46; width: 80; height: 60 }
    MouseArea {
        anchors.fill: parent
        enabled: game.active
        onPressed: { game.forceActiveFocus(); game.flap(); }
    }
    MouseArea {
        anchors.fill: perchHit
        enabled: !game.active
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: { game.forceActiveFocus(); game.flap(); }
    }

    // ---- the wire: from off the right edge of the screen, sagging a little ----
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35)
            strokeWidth: 1.4
            fillColor: "transparent"
            startX: game.ax; startY: game.ay
            // quadratic whose midpoint is the perch: control = 2*mid - (a + b)/2
            PathQuad { x: game.bx; y: game.by; controlX: game.perchX; controlY: 2 * game.wireY - (game.ay + game.by) / 2 }
        }
    }
    // a small insulator where the wire ends
    Rectangle {
        // the clamp holding the wire to the bar's corner
        x: game.ax - 4; y: game.ay - 2
        width: 8; height: 6; radius: 2
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.4)
    }
    Text {
        visible: game.best > 0 && game.phase === "perched"
        x: game.perchX - width / 2; y: game.wireY + 30
        text: "best " + game.best
        color: Theme.fgDim
        opacity: 0.6
        font.family: Theme.font
        font.pixelSize: 10
    }

    // ---- the score, glowing faintly behind the field ----
    Text {
        visible: game.phase !== "perched"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: -80
        y: 70
        text: game.score
        color: Theme.accent
        opacity: 0.22 * (game.phase === "playing" ? 1 : game.pipesAlpha)
        font.family: Theme.font
        font.pixelSize: 140
        font.bold: true
    }

    // ---- the shards ----
    Repeater {
        model: game.pipes.length
        Item {
            id: pp
            required property int index
            readonly property var p: game.pipes[index] ?? { x: -999, gapY: 0 }
            readonly property real fade: Math.max(0, Math.min(1, (p.x + game.pipeW) / game.fadeEdge))
                                       * Math.max(0, Math.min(1, (game.areaW - p.x) / 80)) * game.pipesAlpha
            x: p.x; y: 0
            width: game.pipeW; height: game.areaH
            opacity: fade
            visible: fade > 0.01
            // top shard and bottom shard, slanted like the shell's panels
            Repeater {
                model: 2
                Shape {
                    id: shard
                    required property int index
                    readonly property bool isTop: index === 0
                    readonly property real y0: isTop ? 0 : pp.p.gapY + game.gapH / 2
                    readonly property real y1: isTop ? pp.p.gapY - game.gapH / 2 : game.areaH
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        // glass: faint at the outer end, brighter towards the gap
                        fillGradient: LinearGradient {
                            x1: 0; y1: shard.isTop ? shard.y0 : shard.y1; x2: 0; y2: shard.isTop ? shard.y1 : shard.y0
                            GradientStop { position: 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.03) }
                            GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32) }
                        }
                        strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.9)
                        strokeWidth: 1.3
                        joinStyle: ShapePath.MiterJoin
                        // a slanted tip at the gap: top shard (0,0)-(W,0)-(W,y1-8)-(0,y1); bottom (0,y0+8)-(W,y0)-(W,y1)-(0,y1)
                        startX: 0; startY: shard.isTop ? 0 : shard.y0 + 8
                        PathLine { x: game.pipeW; y: shard.isTop ? 0 : shard.y0 }
                        PathLine { x: game.pipeW; y: shard.isTop ? shard.y1 - 8 : shard.y1 }
                        PathLine { x: 0; y: shard.y1 }
                        PathLine { x: 0; y: shard.isTop ? 0 : shard.y0 + 8 }
                    }
                }
            }
        }
    }

    // ---- the bird ----
    Item {
        id: bird
        x: game.birdX + game.birdXo - 16
        y: game.birdY - 14
        width: 32; height: 28
        rotation: game.tilt
        scale: 1.35
        transformOrigin: Item.Center
        // body
        Rectangle {
            x: 4; y: 4; width: 24; height: 20; radius: 10
            color: Theme.accent
            antialiasing: true
        }
        // belly
        Rectangle { x: 7; y: 13; width: 13; height: 9; radius: 5; color: Qt.lighter(Theme.accent, 1.35); antialiasing: true }
        // wing: folded when perched, beating while flying
        Rectangle {
            id: wing
            x: 13; y: 9; width: 12; height: 8; radius: 4
            color: Qt.darker(Theme.accent, 1.3)
            antialiasing: true
            transformOrigin: Item.Left
            property real beat: 0
            rotation: game.phase === "perched" ? 0 : -35 + 50 * beat
            SequentialAnimation on beat {
                running: game.phase === "playing" || game.phase === "returning"
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 110 }
                NumberAnimation { from: 1; to: 0; duration: 110 }
            }
        }
        // beak (facing left, the way it flies)
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.warn
                strokeColor: "transparent"
                startX: 5; startY: 10
                PathLine { x: -2; y: 13 }
                PathLine { x: 5; y: 15 }
            }
        }
        // eye, with an occasional blink
        Rectangle {
            id: eye
            x: 8; y: 8; width: 5; height: game.phase === "falling" ? 1.5 : (blink.on ? 1 : 5); radius: 2.5
            color: Theme.bg
        }
        // tail
        Rectangle { x: 25; y: 8; width: 7; height: 4; radius: 2; color: Qt.darker(Theme.accent, 1.2); rotation: -20; antialiasing: true }
        // feet on the wire
        Row {
            visible: game.phase === "perched"
            x: 11; y: 23
            spacing: 5
            Repeater { model: 2; Rectangle { width: 1.5; height: 5; color: Theme.fgDim } }
        }
    }
    QtObject { id: blink; property bool on: false }
    Timer {
        running: game.phase === "perched"
        interval: 3800 + Math.random() * 2500
        repeat: true
        onTriggered: { blink.on = true; blinkOff.restart(); }
    }
    Timer { id: blinkOff; interval: 130; onTriggered: blink.on = false }
    // hint while hovering the bird
    Text {
        visible: game.phase === "perched" && perchHover.hovered
        x: game.perchX - width / 2; y: game.wireY + 14
        text: "click to fly"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 10
    }
    HoverHandler { id: perchHover; target: perchHit }
}
