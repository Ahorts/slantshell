import QtQuick
import ".."

// Flappy Bird on the desktop. Click the play area (or press Space / Up after clicking it once
// to focus the widget) to flap. Colours follow the theme.
Card {
    id: card

    // ---- Tunables ----
    readonly property real areaW: 260
    readonly property real areaH: 320
    readonly property real groundH: 30
    readonly property real birdX: 70
    readonly property real birdR: 12
    readonly property real gravity: 950      // px/s^2
    readonly property real flapSpeed: -320   // px/s
    readonly property real pipeSpeed: 120    // px/s
    readonly property real pipeW: 46
    readonly property real gapH: 100
    readonly property real pipeSpacing: 170

    // ---- State ----
    property bool auto: false        // autopilot (shell: `ipc call flappy on`)
    property string phase: "ready"   // ready | playing | dead
    property int score: 0
    property int best: 0
    property real birdY: areaH / 2
    property real vy: 0
    property real bob: 0             // idle bobbing offset while "ready"
    property bool canRestart: true
    readonly property var pipes: [p0, p1, p2]

    width: areaW + 32
    height: areaH + 32 + 34
    focus: true

    function randomGap() {
        const margin = 40;
        return margin + gapH / 2 + Math.random() * (areaH - groundH - gapH - margin * 2);
    }

    function reset() {
        birdY = areaH / 2;
        vy = 0;
        score = 0;
        for (let i = 0; i < pipes.length; i++) {
            pipes[i].x = areaW + 80 + i * pipeSpacing;
            pipes[i].gapY = randomGap();
            pipes[i].scored = false;
        }
        phase = "ready";
    }

    function die() {
        if (phase === "dead") return;
        phase = "dead";
        best = Math.max(best, score);
        canRestart = false;
        restartLock.restart();
    }

    function flap() {
        if (phase === "ready") phase = "playing";
        if (phase === "playing") vy = flapSpeed;
        else if (phase === "dead" && canRestart) reset();
    }

    // Autopilot: aim a little below the middle of the next gap and flap when below that line.
    function botThink() {
        let best = null;
        for (let i = 0; i < pipes.length; i++) {
            const p = pipes[i];
            if (p.x + pipeW > birdX - birdR && (best === null || p.x < best.x)) best = p;
        }
        const target = best ? best.gapY + 18 : areaH / 2;
        if (birdY > target && vy > -120) vy = flapSpeed;
    }

    function step(dt) {
        if (auto) botThink();
        vy += gravity * dt;
        birdY += vy * dt;

        for (let i = 0; i < pipes.length; i++) {
            const p = pipes[i];
            p.x -= pipeSpeed * dt;
            if (p.x + pipeW < 0) {
                p.x += pipes.length * pipeSpacing;
                p.gapY = randomGap();
                p.scored = false;
            }
            if (!p.scored && p.x + pipeW < birdX - birdR) {
                p.scored = true;
                score += 1;
            }
            // collision with this pipe pair
            if (birdX + birdR > p.x && birdX - birdR < p.x + pipeW) {
                if (birdY - birdR < p.gapY - gapH / 2 || birdY + birdR > p.gapY + gapH / 2) die();
            }
        }

        if (birdY + birdR > areaH - groundH) { birdY = areaH - groundH - birdR; die(); }
        if (birdY - birdR < 0) { birdY = birdR; vy = 0; }
    }

    Component.onCompleted: reset()

    Keys.onSpacePressed: flap()
    Keys.onUpPressed: flap()

    FrameAnimation {
        running: card.phase === "playing"
        onTriggered: card.step(Math.min(frameTime, 0.05))
    }

    // Gentle idle bob while waiting to start.
    // Only while hovered: an animation that loops forever keeps the whole desktop layer redrawing.
    HoverHandler { id: hoverBob }
    SequentialAnimation {
        running: card.phase === "ready" && hoverBob.hovered
        loops: Animation.Infinite
        NumberAnimation { target: card; property: "bob"; from: -5; to: 5; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { target: card; property: "bob"; from: 5; to: -5; duration: 600; easing.type: Easing.InOutSine }
    }

    // Autopilot: start and restart games on its own.
    Timer {
        running: card.auto
        interval: 300
        repeat: true
        onTriggered: if (card.phase === "ready" || (card.phase === "dead" && card.canRestart)) card.flap()
    }

    Timer { id: restartLock; interval: 450; onTriggered: card.canRestart = true }

    component PipeItem: Item {
        property real gapY: 100
        property bool scored: false
        width: card.pipeW
        height: card.areaH - card.groundH

        Rectangle {
            width: parent.width
            height: Math.max(0, parent.gapY - card.gapH / 2)
            color: Theme.good
            border.color: Qt.darker(Theme.good, 1.5)
            border.width: 2
        }
        Rectangle {
            y: parent.gapY + card.gapH / 2
            width: parent.width
            height: Math.max(0, parent.height - y)
            color: Theme.good
            border.color: Qt.darker(Theme.good, 1.5)
            border.width: 2
        }
    }

    // ---- Header ----
    Row {
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        height: 22
        spacing: 8

        Text {
            width: parent.width - scoreText.width - 8
            text: card.auto ? "Flappy · auto" : "Flappy"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            id: scoreText
            text: "Best " + card.best
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }

    // ---- Play area ----
    Item {
        id: area
        x: 16
        y: 16 + 28
        width: card.areaW
        height: card.areaH
        clip: true

        // Sky
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.bg }
                GradientStop { position: 1.0; color: Qt.darker(Theme.accentContainer, 2.2) }
            }
        }

        PipeItem { id: p0; y: 0 }
        PipeItem { id: p1; y: 0 }
        PipeItem { id: p2; y: 0 }

        // Ground
        Rectangle {
            y: card.areaH - card.groundH
            width: parent.width
            height: card.groundH
            color: Theme.surface
            Rectangle { width: parent.width; height: 2; color: Theme.accentContainer }
        }

        // Bird
        Item {
            id: bird
            x: card.birdX - card.birdR
            y: card.birdY + (card.phase === "ready" ? card.bob : 0) - card.birdR
            width: card.birdR * 2
            height: card.birdR * 2
            rotation: card.phase === "ready" ? 0 : Math.max(-25, Math.min(70, card.vy / 6))
            Behavior on rotation { enabled: card.phase !== "dead"; NumberAnimation { duration: 60 } }

            Rectangle { anchors.fill: parent; radius: width / 2; color: Theme.accent }
            Rectangle { x: 14; y: 6; width: 7; height: 7; radius: 3.5; color: "white"
                Rectangle { x: 3; y: 2.5; width: 3; height: 3; radius: 1.5; color: "#222" } }
            Rectangle { x: 19; y: 12; width: 9; height: 5; radius: 2.5; color: Theme.accentContainer }
        }

        // Score while playing
        Text {
            visible: card.phase === "playing"
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 14 }
            text: card.score
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 40
            font.bold: true
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.5)
        }

        // Overlays
        Text {
            visible: card.phase === "ready"
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 50 }
            horizontalAlignment: Text.AlignHCenter
            text: "Click or press Space\nto flap"
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
        }

        Rectangle {
            visible: card.phase === "dead"
            anchors.centerIn: parent
            width: 190
            height: 96
            radius: Theme.radius
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.9)
            border.color: Theme.accentContainer
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Game over"
                    color: Theme.warn
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Score " + card.score + "   Best " + card.best
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Click to retry"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onPressed: { card.forceActiveFocus(); card.flap(); }
        }
    }
}
