import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// System galaxy (Animated Gargantua black hole + toned-down proximity sparks + Lightning-Sparkle Inspector Link):
//   - Animated Black Hole: combines the Gargantua core with live swirling relativistic plasma streaks,
//     orbiting accretion hotspots that pass behind the upper shadow and across the front face, and a
//     shimmering photon ring.
//   - Subtle proximity sparks: reduced `sparkRange` (56px) and probability so only nearly-touching bubbles
//     occasionally arc.
//   - Selected Bubble Inspector + Lightning Sparkle Link: clicking a bubble opens a rich telemetry card on
//     the left, tethered to the selected bubble by a live multi-strand lightning + drifting sparkle bridge.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    property real appear: wanted ? 1 : 0
    Behavior on appear { NumberAnimation { duration: wanted ? 950 : 400; easing.type: wanted ? Easing.OutCubic : Easing.InCubic } }
    visible: wanted || dim > 0.002 || appear > 0.002

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-galaxy"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // ================================================================= data
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real holeR: 58
    readonly property real diskTilt: -15.5 * Math.PI / 180
    property real t: 0
    property int frameCount: 0
    property var bolts: ({ weak: "M0,0", mid: "M0,0", strong: "M0,0" })

    readonly property var protectedNames: ["qs", "quickshell", "Hyprland", "hyprland", "systemd", "dbus-daemon", "dbus-broker",
        "pipewire", "pipewire-pulse", "wireplumber", "Xwayland", "sh", "bash", "fish", "zsh", "login", "sshd", "polkitd",
        "ps", "head", "xdg-desktop-por", "xdg-desktop-portal", "kwin_wayland"]
    function isProtected(name) { return protectedNames.indexOf(name) >= 0; }

    ListModel { id: bubs }
    property int pending: -1
    property string selected: ""
    property string notice: ""
    property var hist: ({})
    property var selHist: []

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property real temp: 0
    property real memTotalGb: 8.0
    property real memUsedGb: 0.0
    property var prevStat: null

    readonly property var planetDefs: [
        { label: "CPU",    key: "cpu",  colKey: "accent",  orbit: 0, speed: 0.09,  start: 0.45 },
        { label: "Memory", key: "mem",  colKey: "accent2", orbit: 1, speed: 0.068, start: 2.25 },
        { label: "Disk",   key: "disk", colKey: "cont",    orbit: 2, speed: 0.052, start: 4.05 },
        { label: "Temp",   key: "temp", colKey: "warn",    orbit: 3, speed: 0.038, start: 5.35 }
    ]

    function planetPos(idx) {
        const pd = planetDefs[idx];
        const rx = 215 + pd.orbit * 94;
        const ang = pd.start + win.t * pd.speed;
        return {
            x: win.cx + Math.cos(ang) * rx,
            y: win.cy + Math.sin(ang) * rx * 0.56,
            r: 44
        };
    }

    // Jagged lightning path generator
    function boltPath(ax, ay, bx, by, amp) {
        const dx = bx - ax, dy = by - ay, len = Math.hypot(dx, dy) || 1;
        const nx = -dy / len, ny = dx / len, segs = Math.max(3, Math.round(len / 14));
        let d = "M" + ax.toFixed(1) + "," + ay.toFixed(1);
        for (let i = 1; i < segs; i++) {
            const u = i / segs, j = (Math.random() * 2 - 1) * amp * Math.sin(Math.PI * u);
            d += " L" + (ax + dx * u + nx * j).toFixed(1) + "," + (ay + dy * u + ny * j).toFixed(1);
        }
        return d + " L" + bx.toFixed(1) + "," + by.toFixed(1);
    }

    // Subtle proximity lightning (toned down: shorter range & lower trigger rate so it doesn't clutter the field)
    function computeBolts() {
        const sparkRange = 54;
        const B = { weak: "", mid: "", strong: "" };
        const all = [];
        for (let i = 0; i < bubs.count; i++) {
            const b = bubs.get(i);
            if (b.st === "idle") all.push({ x: b.bx, y: b.by, r: b.r });
        }
        for (let i = 0; i < all.length; i++) {
            for (let j = i + 1; j < all.length; j++) {
                const p = all[i], q = all[j];
                const dx = q.x - p.x, dy = q.y - p.y, d = Math.hypot(dx, dy) || 0.01;
                const g = d - p.r - q.r;
                if (g > sparkRange) continue;
                const I = 1 - Math.max(0, g) / sparkRange, ux = dx / d, uy = dy / d;
                const bucket = I > 0.78 ? "strong" : (I > 0.45 ? "mid" : "weak");
                if (Math.random() > (bucket === "strong" ? 0.55 : (bucket === "mid" ? 0.35 : 0.15))) continue;
                const rot = r => {
                    const a = (Math.random() - 0.5) * 0.5;
                    return [(ux * Math.cos(a) - uy * Math.sin(a)) * r, (ux * Math.sin(a) + uy * Math.cos(a)) * r];
                };
                const po = rot(p.r), qo = rot(q.r);
                const ax = p.x + po[0], ay = p.y + po[1], bx = q.x - qo[0], by = q.y - qo[1];
                const amp = Math.min(9, 2 + Math.max(3, g) * 0.12);
                B[bucket] += boltPath(ax, ay, bx, by, amp) + " ";
            }
        }
        return {
            weak: B.weak || "M0,0",
            mid: B.mid || "M0,0",
            strong: B.strong || "M0,0"
        };
    }

    Timer { interval: 2000; repeat: true; running: win.wanted; triggeredOnStart: true; onTriggered: poll.running = true }
    Process {
        id: poll
        command: ["sh", "-c", "ps -u \"$USER\" -o pid=,pcpu=,rss=,comm= --sort=-pcpu | head -120; echo @@TEMP; cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1; echo @@STAT; head -1 /proc/stat; echo @@MEM; grep -E 'MemTotal|MemAvailable' /proc/meminfo; echo @@DISK; df --output=pcent / | tail -1"]
        stdout: StdioCollector { onStreamFinished: win.ingest(text) }
    }

    function ingest(text) {
        const parts = text.split(/@@(?:TEMP|STAT|MEM|DISK)\n/);
        const psText = parts[0] ?? "";
        const tempText = (parts[1] ?? "").trim();
        const statText = (parts[2] ?? "").trim();
        const memText = parts[3] ?? "";
        const diskText = parts[4] ?? "";

        if (tempText !== "") temp = Number(tempText) / 1000;
        const f = statText.split(/\s+/).slice(1).map(Number);
        if (f.length > 4) {
            const idle = f[3] + (f[4] || 0), total = f.reduce((a, b) => a + b, 0);
            if (prevStat) { const dt = total - prevStat.total, di = idle - prevStat.idle; if (dt > 0) cpu = Math.max(0, Math.min(1, 1 - di / dt)); }
            prevStat = { total: total, idle: idle };
        }
        const mt = /MemTotal:\s+(\d+)/.exec(memText), ma = /MemAvailable:\s+(\d+)/.exec(memText);
        if (mt && ma) {
            const totK = Number(mt[1]), availK = Number(ma[1]);
            mem = 1 - availK / totK;
            memTotalGb = totK / 1048576;
            memUsedGb = (totK - availK) / 1048576;
        }
        const dm = /(\d+)%/.exec(diskText);
        if (dm) disk = Number(dm[1]) / 100;

        const groups = {};
        for (const line of psText.split("\n")) {
            const m = /^\s*(\d+)\s+([\d.]+)\s+(\d+)\s+(.+?)\s*$/.exec(line);
            if (!m) continue;
            const name = m[4];
            if (name === "ps" || name === "head") continue;
            const g = groups[name] ?? (groups[name] = { name: name, cpu: 0, rss: 0, pids: [] });
            g.cpu += Number(m[2]); g.rss += Number(m[3]); g.pids.push(m[1]);
        }
        const list = Object.values(groups).sort((a, b) => (b.cpu - a.cpu) || (b.rss - a.rss)).slice(0, 14);
        const names = list.map(g => g.name);

        for (let i = bubs.count - 1; i >= 0; i--) {
            const b = bubs.get(i);
            if (names.indexOf(b.name) < 0 && i !== pending && i !== dragIndex && b.st === "idle") bubs.remove(i);
        }
        for (let rankIdx = 0; rankIdx < list.length; rankIdx++) {
            const g = list[rankIdx];
            const h = hist[g.name] ?? [];
            h.push(g.cpu); if (h.length > 40) h.shift();
            hist[g.name] = h;
            let idx = -1;
            for (let i = 0; i < bubs.count; i++) if (bubs.get(i).name === g.name) { idx = i; break; }
            const mb = g.rss / 1024;
            const r = Math.max(38, Math.min(88, 26 + Math.sqrt(mb) * 1.42));
            const props = { cpu: g.cpu, mb: mb, count: g.pids.length, pids: g.pids.join(" "), r: r, prot: isProtected(g.name), rank: rankIdx + 1 };
            if (idx >= 0) { for (const k in props) bubs.setProperty(idx, k, props[k]); }
            else {
                const ang = Math.random() * Math.PI * 2, rad = 230 + Math.random() * 250;
                const sp = 36 + Math.random() * 36, tang = ang + Math.PI / 2;
                bubs.append(Object.assign({
                    name: g.name, st: "idle", spin: 0, wobble: 0,
                    bx: cx + Math.cos(ang) * rad * 1.28, by: cy + Math.sin(ang) * rad * 0.78,
                    vx: Math.cos(tang) * sp, vy: Math.sin(tang) * sp
                }, props));
            }
        }
        if (selected !== "") selHist = (hist[selected] ?? []).slice();
    }

    // ================================================================= physics
    property int dragIndex: -1
    property real mfx: cx
    property real mfy: cy
    property bool holeHot: false

    property real zoomTarget: 1
    property real zoom: zoomTarget
    Behavior on zoom { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    function toField(mx, my) { return Qt.point(cx + (mx - cx) / zoom, cy + (my - cy) / zoom); }

    FrameAnimation {
        running: win.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.033);
            win.t += dt;
            if (win.wanted) {
                win.step(dt);
                holeBackCanvas.requestPaint();
                holeFrontCanvas.requestPaint();
                if (win.selected !== "") cardLinkCanvas.requestPaint();
                if (++win.frameCount % 4 === 0) win.bolts = win.computeBolts();
            }
        }
    }

    function step(dt) {
        const n = bubs.count;
        const margin = 60;
        let hot = false;
        for (let i = 0; i < n; i++) {
            const b = bubs.get(i);
            let x = b.bx, y = b.by, vx = b.vx, vy = b.vy, wob = b.wobble * Math.exp(-4.2 * dt);
            const dx = cx - x, dy = cy - y, d = Math.max(1, Math.hypot(dx, dy));
            const ux = dx / d, uy = dy / d;

            if (b.st === "sucked") {
                const ang = Math.atan2(y - cy, x - cx) + 5.8 * dt;
                const nd = d * (1 - 2.5 * dt) - 15 * dt;
                x = cx + Math.cos(ang) * nd; y = cy + Math.sin(ang) * nd;
                bubs.setProperty(i, "bx", x); bubs.setProperty(i, "by", y);
                bubs.setProperty(i, "spin", b.spin + dt);
                if (nd < 10) bubs.setProperty(i, "st", "gone");
                continue;
            }
            if (i === dragIndex) {
                vx = Math.max(-2200, Math.min(2200, vx + ((mfx - x) * 140 - vx * 16) * dt));
                vy = Math.max(-2200, Math.min(2200, vy + ((mfy - y) * 140 - vy * 16) * dt));
                x += vx * dt; y += vy * dt;
                if (Math.hypot(cx - x, cy - y) < holeR + b.r * 0.55 + 46) hot = true;
            } else if (i === pending) {
                const tx = cx - ux * (holeR + b.r * 0.4), ty = cy - uy * (holeR + b.r * 0.4);
                x += (tx - x) * Math.min(1, 6 * dt); y += (ty - y) * Math.min(1, 6 * dt); vx = 0; vy = 0;
            } else {
                const swirl = 18, pull = 7 + d * 0.01;
                vx += (ux * pull - uy * swirl) * dt; vy += (uy * pull + ux * swirl) * dt;
                const keep = holeR + b.r + 68;
                if (d < keep) { const push = (keep - d) * 15; vx -= ux * push * dt; vy -= uy * push * dt; }
                const damp = Math.exp(-0.55 * dt), sp = Math.hypot(vx, vy);
                vx *= damp; vy *= damp;
                if (sp < 28) { vx += (-uy) * 24 * dt; vy += ux * 24 * dt; }
                x += vx * dt; y += vy * dt;
            }
            if (x < margin + b.r) { x = margin + b.r; vx = Math.abs(vx) * 0.72; wob = Math.min(0.2, wob + 0.08); }
            if (x > width - margin - b.r) { x = width - margin - b.r; vx = -Math.abs(vx) * 0.72; wob = Math.min(0.2, wob + 0.08); }
            if (y < 90 + b.r) { y = 90 + b.r; vy = Math.abs(vy) * 0.72; wob = Math.min(0.2, wob + 0.08); }
            if (y > height - margin - b.r) { y = height - margin - b.r; vy = -Math.abs(vy) * 0.72; wob = Math.min(0.2, wob + 0.08); }
            bubs.setProperty(i, "bx", x); bubs.setProperty(i, "by", y);
            bubs.setProperty(i, "vx", vx); bubs.setProperty(i, "vy", vy);
            bubs.setProperty(i, "wobble", wob);
        }
        for (let i = 0; i < n; i++) {
            const a = bubs.get(i);
            if (a.st !== "idle" || i === pending) continue;
            for (let j = i + 1; j < n; j++) {
                const c = bubs.get(j);
                if (c.st !== "idle" || j === pending) continue;
                const dx = c.bx - a.bx, dy = c.by - a.by, d = Math.hypot(dx, dy), min = a.r + c.r + 12;
                if (d >= min || d < 0.01) continue;
                const nx = dx / d, ny = dy / d, over = min - d;
                const ma = a.r * a.r, mc = c.r * c.r, tot = ma + mc;
                const dragA = i === dragIndex, dragC = j === dragIndex;
                const fa = dragA ? 0 : (dragC ? 1 : mc / tot), fc = dragC ? 0 : (dragA ? 1 : ma / tot);
                bubs.setProperty(i, "bx", a.bx - nx * over * fa); bubs.setProperty(i, "by", a.by - ny * over * fa);
                bubs.setProperty(j, "bx", c.bx + nx * over * fc); bubs.setProperty(j, "by", c.by + ny * over * fc);
                const rel = (c.vx - a.vx) * nx + (c.vy - a.vy) * ny;
                if (rel < 0) {
                    const imp = -(1.65) * rel / (1 / ma + 1 / mc);
                    const kick = Math.min(0.18, -rel / 1800);
                    if (!dragA) {
                        bubs.setProperty(i, "vx", a.vx - imp * nx / ma);
                        bubs.setProperty(i, "vy", a.vy - imp * ny / ma);
                        bubs.setProperty(i, "wobble", Math.min(0.22, a.wobble + kick));
                    }
                    if (!dragC) {
                        bubs.setProperty(j, "vx", c.vx + imp * nx / mc);
                        bubs.setProperty(j, "vy", c.vy + imp * ny / mc);
                        bubs.setProperty(j, "wobble", Math.min(0.22, c.wobble + kick));
                    }
                }
            }
        }
        // the stat planets are solid too: they sail through the field on their orbits and shoulder bubbles aside
        // (a planet is never moved by a bubble; a dragged bubble is left alone so you can still throw it past)
        const pls = [];
        for (let k = 0; k < planetDefs.length; k++) pls.push(planetPos(k));
        for (let i = 0; i < bubs.count; i++) {
            const a = bubs.get(i);
            if (a.st !== "idle" || i === pending || i === dragIndex) continue;
            for (const P of pls) {
                const dx = a.bx - P.x, dy = a.by - P.y, d = Math.hypot(dx, dy), min = a.r + P.r + 10;
                if (d >= min || d < 0.01) continue;
                const nx = dx / d, ny = dy / d, over = min - d;
                bubs.setProperty(i, "bx", a.bx + nx * over); bubs.setProperty(i, "by", a.by + ny * over);
                const rel = a.vx * nx + a.vy * ny;
                if (rel < 0) {
                    bubs.setProperty(i, "vx", a.vx - 1.6 * rel * nx);
                    bubs.setProperty(i, "vy", a.vy - 1.6 * rel * ny);
                    bubs.setProperty(i, "wobble", Math.min(0.22, a.wobble + Math.min(0.15, -rel / 1600)));
                }
            }
        }
        for (let i = bubs.count - 1; i >= 0; i--) if (bubs.get(i).st === "gone") {
            if (pending > i) pending--; if (dragIndex > i) dragIndex--;
            bubs.remove(i);
        }
        if (hot !== holeHot) holeHot = hot;
    }

    // ================================================================= ending a program
    function askEnd(i) {
        const b = bubs.get(i);
        if (!b || pending >= 0) return;
        if (b.prot) { say(b.name + " is protected"); pushOut(i); return; }
        pending = i;
        bubs.setProperty(i, "st", "idle");
        confirmTimer.restart();
    }
    function askEndByName(name) { for (let i = 0; i < bubs.count; i++) if (bubs.get(i).name === name) { askEnd(i); return; } }
    function pushOut(i) {
        const b = bubs.get(i);
        const dx = b.bx - cx, dy = b.by - cy, d = Math.max(1, Math.hypot(dx, dy));
        bubs.setProperty(i, "vx", dx / d * 340); bubs.setProperty(i, "vy", dy / d * 340);
    }
    function cancel() {
        if (pending < 0) return;
        pushOut(pending);
        pending = -1;
        confirmTimer.stop();
    }
    function confirm() {
        if (pending < 0) return;
        const b = bubs.get(pending);
        Quickshell.execDetached(["kill", "-TERM"].concat(b.pids.split(" ")));
        bubs.setProperty(pending, "st", "sucked");
        say("Asked " + b.name + " to quit");
        if (selected === b.name) selected = "";
        pending = -1;
        confirmTimer.stop();
    }
    function say(msg) { notice = msg; noticeTimer.restart(); }
    Timer { id: confirmTimer; interval: 7000; onTriggered: win.cancel() }
    Timer { id: noticeTimer; interval: 2600; onTriggered: win.notice = "" }

    function bubbleAt(fx, fy) {
        let best = -1, bestD = 1e9;
        for (let i = 0; i < bubs.count; i++) {
            const b = bubs.get(i);
            if (b.st !== "idle" || i === pending) continue;
            const d = Math.hypot(fx - b.bx, fy - b.by);
            if (d <= b.r && d < bestD) { best = i; bestD = d; }
        }
        return best;
    }
    function select(name) {
        selected = (selected === name) ? "" : name;
        selHist = selected !== "" ? (hist[selected] ?? []).slice() : [];
    }

    onWantedChanged: {
        if (wanted) { pending = -1; dragIndex = -1; selected = ""; notice = ""; zoomTarget = 1; Qt.callLater(() => keys.forceActiveFocus()); }
        else { bubs.clear(); hist = ({}); }
    }

    // ================================================================= view
    Rectangle { anchors.fill: parent; color: "#03040a"; opacity: 0.94 * win.dim }

    Item {
        id: field
        anchors.fill: parent
        scale: win.zoom * (0.84 + 0.16 * win.appear)
        transformOrigin: Item.Center
        opacity: win.dim

        readonly property real parX: (win.mfx - win.cx) * 0.05
        readonly property real parY: (win.mfy - win.cy) * 0.05

        // Far starfield
        Image {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: field.parX * 0.35
            anchors.verticalCenterOffset: field.parY * 0.35
            width: Math.max(parent.width, 1920) * 1.05
            height: Math.max(parent.height, 1080) * 1.05
            source: "assets/space/stars-far.png"
            fillMode: Image.Tile
            opacity: 0.75 * win.appear
        }

        // =====================================================================
        // ANIMATED LIVING GARGANTUA BLACK HOLE (3-Layer Relativistic Engine)
        //   1. holeBackCanvas  (z: 1): Breathing gravitational lensing halo + swirling back accretion disk
        //   2. holeShadow      (z: 2): Pitch-black event horizon + rotating Doppler photon ring
        //   3. holeFrontCanvas (z: 3): Animated front accretion plasma disk + orbiting plasma jets crossing the face
        // =====================================================================
        Item {
            id: hole
            x: win.cx + field.parX * 0.5
            y: win.cy + field.parY * 0.5
            scale: (0.4 + 0.6 * win.appear) * (win.holeHot || win.pending >= 0 ? 1.15 : 1.0)
            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

            // Layer 1 (BACK): Lensed upper/lower photon arches + swirling back half of accretion disk
            Canvas {
                id: holeBackCanvas
                x: -280; y: -240
                width: 560; height: 480
                z: 1

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const cx = 280, cy = 240;
                    const R = win.holeR;
                    const hot = win.holeHot || win.pending >= 0;
                    const c1 = hot ? Theme.warn : Theme.accent;
                    const c2 = Theme.accent2;
                    const pulse = 0.5 + 0.5 * Math.sin(win.t * 1.8);

                    // Deep radial gravitational nebula
                    const amb = ctx.createRadialGradient(cx, cy, R * 0.5, cx, cy, 235);
                    amb.addColorStop(0.0, Qt.rgba(c1.r, c1.g, c1.b, hot ? 0.50 : (0.28 + 0.06 * pulse)));
                    amb.addColorStop(0.38, Qt.rgba(c2.r, c2.g, c2.b, 0.14));
                    amb.addColorStop(0.75, Qt.rgba(c1.r, c1.g, c1.b, 0.03));
                    amb.addColorStop(1.0, "transparent");
                    ctx.fillStyle = amb;
                    ctx.beginPath();
                    ctx.arc(cx, cy, 235, 0, Math.PI * 2);
                    ctx.fill();

                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(win.diskTilt);

                    // Gravitationally lensed upper & lower photon arches (warped over top & bottom of shadow)
                    for (let side = -1; side <= 1; side += 2) {
                        ctx.save();
                        ctx.scale(1.22, 0.98 + 0.02 * Math.sin(win.t * 2.1 + side));
                        const startA = side < 0 ? Math.PI * 1.06 : Math.PI * 0.06;
                        const endA   = side < 0 ? Math.PI * 1.94 : Math.PI * 0.94;

                        ctx.beginPath();
                        ctx.arc(0, side * 4, R + 13, startA, endA);
                        ctx.strokeStyle = Qt.rgba(c1.r, c1.g, c1.b, 0.26);
                        ctx.lineWidth = 20;
                        ctx.stroke();

                        ctx.beginPath();
                        ctx.arc(0, side * 3, R + 8, startA, endA);
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.45 + 0.12 * pulse);
                        ctx.lineWidth = 4.2;
                        ctx.stroke();
                        ctx.restore();
                    }

                    // Back half of the accretion disk (angles PI .. 2*PI)
                    ctx.save();
                    ctx.scale(1.0, 0.25);
                    const backBands = [
                        { r: 196, w: 44, col: Qt.rgba(c2.r, c2.g, c2.b, 0.14) },
                        { r: 160, w: 32, col: Qt.rgba(c1.r, c1.g, c1.b, 0.28) },
                        { r: 128, w: 20, col: Qt.rgba(c1.r, c1.g, c1.b, 0.52) },
                        { r: 102, w: 9,  col: Qt.rgba(1, 1, 1, 0.74) }
                    ];
                    for (const b of backBands) {
                        ctx.beginPath();
                        ctx.arc(0, 0, b.r, Math.PI * 0.95, Math.PI * 2.05);
                        ctx.strokeStyle = b.col;
                        ctx.lineWidth = b.w;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }

                    // Animated plasma streaks orbiting along the back half (PI .. 2*PI)
                    for (let i = 0; i < 6; i++) {
                        const aCenter = Math.PI + ((win.t * (1.1 + i * 0.17) + i * 1.05) % Math.PI);
                        const span = 0.28 + (i % 3) * 0.08;
                        const a0 = Math.max(Math.PI + 0.05, aCenter - span);
                        const a1 = Math.min(Math.PI * 2 - 0.05, aCenter + span);
                        if (a1 > a0) {
                            ctx.beginPath();
                            ctx.arc(0, 0, 108 + i * 14, a0, a1);
                            ctx.strokeStyle = i % 2 === 0
                                ? Qt.rgba(1, 1, 1, 0.55)
                                : Qt.rgba(c1.r, c1.g, c1.b, 0.70);
                            ctx.lineWidth = 3.5;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }
                    }

                    ctx.restore();
                    ctx.restore();
                }
            }

            // Layer 2 (MIDDLE): Pitch-black Event Horizon Sphere + shimmering photon ring
            Rectangle {
                id: holeShadow
                z: 2
                x: -win.holeR; y: -win.holeR
                width: win.holeR * 2; height: win.holeR * 2
                radius: win.holeR
                color: "#000000"
                border.color: Qt.rgba(1, 1, 1, 0.68)
                border.width: 1.6
            }

            // Layer 3 (FRONT — z: 3): Animated front accretion disk cutting RIGHT ACROSS the black hole face!
            Canvas {
                id: holeFrontCanvas
                x: -280; y: -240
                width: 560; height: 480
                z: 3

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const cx = 280, cy = 240;
                    const hot = win.holeHot || win.pending >= 0;
                    const c1 = hot ? Theme.warn : Theme.accent;
                    const c2 = Theme.accent2;

                    ctx.save();
                    ctx.translate(cx, cy);
                    ctx.rotate(win.diskTilt);
                    ctx.scale(1.0, 0.25);

                    const frontBands = [
                        { r: 200, w: 46, a0: -0.04, a1: Math.PI + 0.04, col: Qt.rgba(c2.r, c2.g, c2.b, 0.16) },
                        { r: 164, w: 34, a0: -0.03, a1: Math.PI + 0.03, col: Qt.rgba(c1.r, c1.g, c1.b, 0.36) },
                        { r: 130, w: 20, a0: -0.02, a1: Math.PI + 0.02, col: Qt.rgba(c1.r, c1.g, c1.b, 0.72) },
                        { r: 104, w: 8,  a0: 0.02,  a1: Math.PI - 0.02, col: Qt.rgba(1, 1, 1, 0.94) }
                    ];
                    for (const b of frontBands) {
                        ctx.beginPath();
                        ctx.arc(0, 0, b.r, b.a0, b.a1);
                        ctx.strokeStyle = b.col;
                        ctx.lineWidth = b.w;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }

                    // Swirling relativistic plasma filaments & hotspots sweeping across the front of the black hole
                    for (let i = 0; i < 8; i++) {
                        const phase = (win.t * (1.25 + i * 0.16) + i * 0.85) % Math.PI;
                        const span = 0.32 + (i % 2) * 0.12;
                        const aStart = Math.max(0.03, phase - span * 0.5);
                        const aEnd = Math.min(Math.PI - 0.03, phase + span * 0.5);
                        const rad = 106 + (i % 5) * 16;
                        if (aEnd > aStart) {
                            ctx.beginPath();
                            ctx.arc(0, 0, rad, aStart, aEnd);
                            ctx.strokeStyle = i % 2 === 0
                                ? Qt.rgba(1, 1, 1, 0.82)
                                : Qt.rgba(c1.r, c1.g, c1.b, 0.88);
                            ctx.lineWidth = i % 2 === 0 ? 3.8 : 2.8;
                            ctx.lineCap = "round";
                            ctx.stroke();
                        }
                    }

                    ctx.restore();
                }
            }
        }

        // Near starfield
        Image {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: field.parX * 0.9
            anchors.verticalCenterOffset: field.parY * 0.9
            width: Math.max(parent.width, 1920) * 1.08
            height: Math.max(parent.height, 1080) * 1.08
            source: "assets/space/stars-near.png"
            fillMode: Image.Tile
            opacity: 0.85 * win.appear
        }

        // ---- Subtle Proximity Micro-Sparks ----
        Shape {
            id: boltShape
            anchors.fill: parent
            opacity: win.appear * 0.78

            ShapePath {
                strokeColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                strokeWidth: 5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: (win.bolts.mid + " " + win.bolts.strong) || "M0,0" }
            }
            ShapePath {
                strokeColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.30)
                strokeWidth: 1.0
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: win.bolts.weak || "M0,0" }
            }
            ShapePath {
                strokeColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.60)
                strokeWidth: 1.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: win.bolts.mid || "M0,0" }
            }
            ShapePath {
                strokeColor: "#ffffff"
                strokeWidth: 1.9
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: win.bolts.strong || "M0,0" }
            }
        }

        // ---- System Dials (Orbiting Planets) ----
        Repeater {
            model: win.planetDefs
            Item {
                id: planet
                required property var modelData
                required property int index
                readonly property real val: modelData.key === "temp" ? Math.max(0, Math.min(1, (win.temp - 25) / 75)) : win[modelData.key]
                readonly property color col: modelData.colKey === "accent"
                    ? Theme.accent
                    : (modelData.colKey === "accent2" ? Theme.accent2 : (modelData.colKey === "cont" ? (val > 0.9 ? Theme.warn : Theme.accentContainer) : Theme.warn))
                readonly property real rx: 215 + modelData.orbit * 94
                readonly property real ang: modelData.start + win.t * modelData.speed
                width: 96; height: 96
                x: win.cx + Math.cos(ang) * rx - width / 2
                y: win.cy + Math.sin(ang) * rx * 0.56 - height / 2
                opacity: Math.max(0, Math.min(1, win.appear * 2.2 - modelData.orbit * 0.25))
                scale: 0.72 + 0.28 * Math.min(1, win.appear * 1.6)

                property real shown: val
                Behavior on shown { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: 48; centerY: 48; centerRadius: 64; focalX: 48; focalY: 48
                            GradientStop { position: 0.0; color: Qt.rgba(planet.col.r, planet.col.g, planet.col.b, 0.28) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        PathAngleArc { centerX: 48; centerY: 48; radiusX: 64; radiusY: 64; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Qt.rgba(planet.col.r, planet.col.g, planet.col.b, 0.24)
                        strokeWidth: 4.5
                        fillColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88)
                        PathAngleArc { centerX: 48; centerY: 48; radiusX: 38; radiusY: 38; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: planet.col
                        strokeWidth: 4.5
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathAngleArc { centerX: 48; centerY: 48; radiusX: 38; radiusY: 38; startAngle: -90; sweepAngle: Math.max(2, planet.shown * 360) }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: planet.modelData.key === "temp"
                            ? Math.round(win.temp) + "°"
                            : (planet.modelData.key === "mem" ? win.memUsedGb.toFixed(1) + "G" : Math.round(planet.val * 100) + "%")
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: planet.modelData.label
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }
        }

        // ---- Program Bubbles ----
        Repeater {
            model: bubs

            Item {
                id: bub
                required property string name
                required property real cpu
                required property real mb
                required property int count
                required property real r
                required property real bx
                required property real by
                required property string st
                required property bool prot
                required property real spin
                required property real wobble

                readonly property bool isSel: win.selected === name
                readonly property bool isDrag: win.dragIndex >= 0 && bubs.get(win.dragIndex)?.name === name
                readonly property color col: Qt.rgba(
                    Theme.accent.r + (Theme.warn.r - Theme.accent.r) * Math.min(1, cpu / 55),
                    Theme.accent.g + (Theme.warn.g - Theme.accent.g) * Math.min(1, cpu / 55),
                    Theme.accent.b + (Theme.warn.b - Theme.accent.b) * Math.min(1, cpu / 55), 1)

                width: r * 2; height: r * 2
                x: bx - r; y: by - r
                property real born: 0
                Component.onCompleted: bornAnim.start()
                NumberAnimation on born { id: bornAnim; running: false; from: 0; to: 1; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                readonly property real baseScale: Math.max(0.001, born) * (st === "sucked" ? Math.max(0.02, 1 - spin * 1.4) : 1) * (isDrag ? 1.08 : 1)
                transform: Scale {
                    origin.x: bub.r; origin.y: bub.r
                    xScale: bub.baseScale * (1 + Math.sin(win.t * 22) * bub.wobble)
                    yScale: bub.baseScale * (1 - Math.sin(win.t * 22) * bub.wobble)
                }
                rotation: st === "sucked" ? spin * 400 : 0
                opacity: win.appear

                Shape {
                    anchors.fill: parent
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: bub.r; centerY: bub.r; centerRadius: bub.r + 16; focalX: bub.r; focalY: bub.r
                            GradientStop { position: 0.60; color: Qt.rgba(bub.col.r, bub.col.g, bub.col.b, bub.isSel || bub.isDrag ? 0.45 : 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        PathAngleArc { centerX: bub.r; centerY: bub.r; radiusX: bub.r + 16; radiusY: bub.r + 16; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: bub.isSel || bub.isDrag ? "#ffffff" : Qt.rgba(bub.col.r, bub.col.g, bub.col.b, 0.85)
                        strokeWidth: bub.isSel || bub.isDrag ? 2.8 : 1.6
                        fillGradient: RadialGradient {
                            centerX: bub.r; centerY: bub.r; centerRadius: bub.r
                            focalX: bub.r * 0.68; focalY: bub.r * 0.60
                            GradientStop { position: 0.0; color: Qt.rgba(bub.col.r, bub.col.g, bub.col.b, 0.16) }
                            GradientStop { position: 0.72; color: Qt.rgba(bub.col.r, bub.col.g, bub.col.b, 0.30) }
                            GradientStop { position: 1.0; color: Qt.rgba(bub.col.r, bub.col.g, bub.col.b, 0.62) }
                        }
                        PathAngleArc { centerX: bub.r; centerY: bub.r; radiusX: bub.r - 1.5; radiusY: bub.r - 1.5; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.30)
                        strokeWidth: 2.4
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathAngleArc { centerX: bub.r; centerY: bub.r; radiusX: bub.r * 0.74; radiusY: bub.r * 0.74; startAngle: 205; sweepAngle: 42 }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    width: bub.r * 1.7
                    spacing: 1
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: (bub.prot ? "󰌾 " : "") + bub.name
                        color: Theme.fg
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Math.max(11, Math.min(16, bub.r / 4.2))
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: bub.cpu >= 0.5
                            ? (bub.cpu.toFixed(1) + "%" + (bub.count > 1 ? " · ×" + bub.count : ""))
                            : (Math.round(bub.mb) + "M" + (bub.count > 1 ? " · ×" + bub.count : ""))
                        color: Qt.lighter(bub.col, 1.25)
                        font.family: Theme.font
                        font.pixelSize: Math.max(9, Math.min(13, bub.r / 5.2))
                    }
                }
            }
        }
    }

    // =========================================================================
    // LIGHTNING SPARKLE LINK TETHER (connects Inspector Card to Selected Bubble!)
    // =========================================================================
    Canvas {
        id: cardLinkCanvas
        anchors.fill: parent
        visible: card.inOut > 0.02 && card.b !== null
        opacity: card.inOut * win.dim
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const b = card.b;
            if (!b) return;

            // Convert bubble world coordinates into screen coordinates (accounting for zoom)
            const bx = win.cx + (b.bx - win.cx) * win.zoom;
            const by = win.cy + (b.by - win.cy) * win.zoom;
            const br = b.r * win.zoom;

            // Anchor on the right edge of the Inspector Card
            const sx = card.x + card.width;
            const sy = card.y + card.height * 0.42;

            const dx = bx - sx, dy = by - sy;
            const dist = Math.hypot(dx, dy);
            if (dist < br + 12) return;
            const ux = dx / dist, uy = dy / dist;
            const nx = -uy, ny = ux;

            // Terminate cleanly at the selected bubble's rim
            const ex = bx - ux * (br + 4);
            const ey = by - uy * (br + 4);

            // 1. Wide soft plasma glow under-bridge
            ctx.beginPath();
            const steps = 32;
            for (let s = 0; s <= steps; s++) {
                const u = s / steps;
                const env = Math.sin(u * Math.PI);
                const wv = Math.sin(u * 9 - win.t * 7) * 10 * env;
                const px = sx + (ex - sx) * u + nx * wv;
                const py = sy + (ey - sy) * u + ny * wv;
                if (s === 0) ctx.moveTo(px, py);
                else ctx.lineTo(px, py);
            }
            ctx.strokeStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22);
            ctx.lineWidth = 9;
            ctx.lineCap = "round";
            ctx.stroke();

            // 2. Dual crackling lightning strands
            for (let strand = 0; strand < 2; strand++) {
                ctx.beginPath();
                for (let s = 0; s <= steps; s++) {
                    const u = s / steps;
                    const env = Math.sin(u * Math.PI);
                    const wave = Math.sin(u * 14 - win.t * (8 + strand * 3) + strand * 2.1) * (6 + strand * 3) * env
                               + Math.cos(u * 29 + win.t * 15 + strand) * 2.5 * env;
                    const px = sx + (ex - sx) * u + nx * wave;
                    const py = sy + (ey - sy) * u + ny * wave;
                    if (s === 0) ctx.moveTo(px, py);
                    else ctx.lineTo(px, py);
                }
                ctx.strokeStyle = strand === 0
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.92)
                    : Qt.rgba(1, 1, 1, 0.78);
                ctx.lineWidth = strand === 0 ? 2.4 : 1.2;
                ctx.stroke();
            }

            // 3. Drifting sparkle stars along the lightning bridge
            for (let k = 0; k < 9; k++) {
                const u = ((win.t * (0.38 + (k % 3) * 0.12) + k * 0.11) % 1.0);
                const env = Math.sin(u * Math.PI);
                const offset = Math.sin(u * 10 - win.t * 6 + k * 1.7) * 11 * env;
                const spx = sx + (ex - sx) * u + nx * offset;
                const spy = sy + (ey - sy) * u + ny * offset;
                const sr = (1.8 + (k % 3) * 1.1) * (0.6 + 0.4 * Math.sin(win.t * 9 + k));

                // 4-point star sparkle
                ctx.save();
                ctx.translate(spx, spy);
                ctx.rotate(win.t * 2 + k);
                ctx.beginPath();
                ctx.moveTo(-sr * 2.2, 0); ctx.lineTo(sr * 2.2, 0);
                ctx.moveTo(0, -sr * 2.2); ctx.lineTo(0, sr * 2.2);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.85 * env);
                ctx.lineWidth = 1.2;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(0, 0, sr, 0, Math.PI * 2);
                ctx.fillStyle = k % 2 === 0 ? "#ffffff" : Theme.accent;
                ctx.fill();
                ctx.restore();
            }

            // 4. Glowing terminal anchor nodes at card edge and bubble rim
            for (const pt of [[sx, sy], [ex, ey]]) {
                ctx.beginPath();
                ctx.arc(pt[0], pt[1], 7, 0, Math.PI * 2);
                ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35);
                ctx.fill();

                ctx.beginPath();
                ctx.arc(pt[0], pt[1], 3.5, 0, Math.PI * 2);
                ctx.fillStyle = "#ffffff";
                ctx.fill();
            }
        }
    }

    // ================================================================= input
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (win.pending >= 0) win.cancel();
                else if (win.selected !== "") win.select(win.selected);
                else win.closeRequested();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Y) win.confirm();
            else return;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property real pressX: 0
        property real pressY: 0
        property bool moved: false
        onPressed: mouse => {
            pressX = mouse.x; pressY = mouse.y; moved = false;
            const p = win.toField(mouse.x, mouse.y);
            win.mfx = p.x; win.mfy = p.y;
            if (win.pending >= 0) return;
            const i = win.bubbleAt(p.x, p.y);
            if (i >= 0) win.dragIndex = i;
        }
        onPositionChanged: mouse => {
            const p = win.toField(mouse.x, mouse.y);
            win.mfx = p.x; win.mfy = p.y;
            if (pressed && Math.hypot(mouse.x - pressX, mouse.y - pressY) > 7) moved = true;
        }
        onReleased: mouse => {
            const i = win.dragIndex;
            win.dragIndex = -1;
            if (i < 0) { if (!moved) { if (win.selected !== "") win.select(win.selected); else if (win.pending < 0) win.closeRequested(); } return; }
            if (!moved) { win.select(bubs.get(i).name); return; }
            if (win.holeHot) win.askEnd(i);
        }
    }
    WheelHandler {
        onWheel: event => { win.zoomTarget = Math.max(0.55, Math.min(1.6, win.zoomTarget * (event.angleDelta.y > 0 ? 1.1 : 1 / 1.1))); }
    }

    // =========================================================================
    // UPGRADED SELECTED PROCESS INSPECTOR CARD (Anserin Telemetry Drawer)
    // =========================================================================
    Rectangle {
        id: card
        readonly property var b: { for (let i = 0; i < bubs.count; i++) if (bubs.get(i).name === win.selected) return bubs.get(i); return null; }
        property real inOut: win.selected !== "" && b !== null ? 1 : 0
        Behavior on inOut { SpringAnimation { spring: 4.2; damping: 0.48; epsilon: 0.002 } }

        width: 364
        height: cardCol.implicitHeight + 48      // fits its content (the button used to be squeezed)
        radius: 26
        x: -width + (width + 32) * inOut
        y: (win.height - height) / 2
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.58)
        border.width: 1.6
        opacity: win.dim * Math.min(1, inOut * 1.6)
        visible: inOut > 0.01

        // Swallow clicks inside the inspector card so clicking it doesn't deselect
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: cardCol
            anchors { fill: parent; margins: 24 }
            spacing: 12

            // ---- Card Header: Status Dot + Process Name + Close Button ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: card.b && card.b.prot ? Theme.accent2 : Theme.accent
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: card.b ? card.b.name : ""
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 22
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.b
                            ? ("PID " + (card.b.pids ? card.b.pids.split(" ")[0] : "—")
                               + "  ·  " + (card.b.prot ? "System Protected" : "User Process"))
                            : ""
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeCardArea.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeCardArea.containsMouse ? Theme.accentText : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: closeCardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.selected = ""
                    }
                }
            }

            // ---- Dual Hero Readout (CPU % + Memory GB with live progress bars) ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // CPU Hero Pill
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: 16
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                    border.width: 1

                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: card.b ? card.b.cpu.toFixed(1) + "%" : "0.0%"
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 22
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "CPU"
                                color: Theme.fgDim
                                font.family: Theme.font
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Rectangle {
                                width: parent.width * Math.min(1, (card.b ? card.b.cpu : 0) / 100)
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                // Memory Hero Pill
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: 16
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.28)
                    border.width: 1

                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: card.b
                                    ? (card.b.mb >= 1024 ? (card.b.mb / 1024).toFixed(2) + " GB" : Math.round(card.b.mb) + " MB")
                                    : "0 MB"
                                color: Theme.accent2
                                font.family: Theme.font
                                font.pixelSize: 20
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "RAM"
                                color: Theme.fgDim
                                font.family: Theme.font
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Rectangle {
                                width: parent.width * Math.min(1, (card.b ? (card.b.mb / 1024) / Math.max(1, win.memTotalGb) : 0))
                                height: parent.height
                                radius: 2
                                color: Theme.accent2
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // ---- Live Activity Sparkline Box ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 106
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.04)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                Text {
                    x: 12; y: 8
                    text: "RECENT CPU ACTIVITY"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 1.1
                }
                Text {
                    anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 8 }
                    text: {
                        const h = win.selHist ?? [];
                        const pk = h.length > 0 ? Math.max(...h) : 0;
                        return "Peak " + pk.toFixed(1) + "%";
                    }
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.bold: true
                }

                Canvas {
                    id: selCanvas
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 28; bottomMargin: 10 }
                    antialiasing: true
                    readonly property var samples: win.selHist
                    onSamplesChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const h = samples ?? [];
                        const w = width, ht = height - 4;
                        if (h.length < 2) return;
                        const mx = Math.max(10, ...h) * 1.18;
                        const stepX = (w - 8) / Math.max(1, h.length - 1);

                        const grad = ctx.createLinearGradient(0, 0, 0, ht);
                        grad.addColorStop(0.0, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.34));
                        grad.addColorStop(1.0, "transparent");

                        ctx.beginPath();
                        ctx.moveTo(0, ht);
                        for (let i = 0; i < h.length; i++) {
                            ctx.lineTo(i * stepX, ht - (h[i] / mx) * (ht - 8));
                        }
                        ctx.lineTo((h.length - 1) * stepX, ht);
                        ctx.closePath();
                        ctx.fillStyle = grad;
                        ctx.fill();

                        ctx.beginPath();
                        for (let i = 0; i < h.length; i++) {
                            const px = i * stepX, py = ht - (h[i] / mx) * (ht - 8);
                            if (i === 0) ctx.moveTo(px, py);
                            else ctx.lineTo(px, py);
                        }
                        ctx.strokeStyle = Theme.accent;
                        ctx.lineWidth = 2.2;
                        ctx.stroke();

                        const lx = (h.length - 1) * stepX;
                        const ly = ht - (h[h.length - 1] / mx) * (ht - 8);
                        ctx.beginPath();
                        ctx.arc(lx, ly, 4.5, 0, Math.PI * 2);
                        ctx.fillStyle = "#ffffff";
                        ctx.fill();
                    }
                }
            }

            // ---- 2x2 Telemetry Fact Grid ----
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 8

                Repeater {
                    model: [
                        { lbl: "Instances / Threads", val: card.b ? (card.b.count + (card.b.count > 1 ? " processes" : " process")) : "—" },
                        { lbl: "Rank by CPU",         val: card.b ? ("#" + (card.b.rank || 1) + " of " + bubs.count) : "—" },
                        { lbl: "Memory Share",        val: card.b ? (((card.b.mb / 1024) / Math.max(1, win.memTotalGb) * 100).toFixed(1) + "% of RAM") : "—" },
                        { lbl: "State",               val: card.b ? (card.b.cpu > 3 ? "Active · Running" : "Idle · Sleeping") : "—" }
                    ]
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.04)
                        Column {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                            spacing: 1
                            Text {
                                text: parent.parent.modelData.lbl
                                color: Theme.fgDim
                                font.family: Theme.font
                                font.pixelSize: 9
                            }
                            Text {
                                text: parent.parent.modelData.val
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }
                }
            }

            // ---- Interactive Terminate / Protected Action Button ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                Layout.minimumHeight: 38
                radius: 19
                color: card.b && card.b.prot
                    ? Qt.rgba(1, 1, 1, 0.06)
                    : (termArea.containsMouse ? Theme.warn : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.18))
                border.color: card.b && card.b.prot ? Qt.rgba(1, 1, 1, 0.12) : Theme.warn
                border.width: 1.2

                Text {
                    anchors.centerIn: parent
                    text: card.b && card.b.prot
                        ? "󰌾  Protected Session Process"
                        : "󰐥  Send Into Event Horizon (SIGTERM)"
                    color: card.b && card.b.prot
                        ? Theme.fgDim
                        : (termArea.containsMouse ? Theme.bg : Theme.warn)
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: termArea
                    anchors.fill: parent
                    enabled: card.b !== null && !card.b.prot
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (card.b) win.askEndByName(card.b.name)
                }
            }
        }
    }

    Rectangle {
        id: bar
        readonly property bool asking: win.pending >= 0
        readonly property string who: asking ? bubs.get(win.pending).name + (bubs.get(win.pending).count > 1 ? " (" + bubs.get(win.pending).count + " processes)" : "") : ""
        height: 48
        radius: 24
        width: Math.max(380, msg.implicitWidth + 56)
        x: Math.round((win.width - width) / 2)
        y: win.height - 92 + (asking || win.notice !== "" ? 0 : 34)
        opacity: (asking || win.notice !== "" ? 1 : 0) * win.dim
        color: asking ? Theme.warn : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
        border.color: asking ? Theme.warn : Theme.accentContainer
        border.width: 1.5
        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Text {
            id: msg
            anchors.centerIn: parent
            text: bar.asking ? "End " + bar.who + "?    Enter · end it     Esc · set it free" : win.notice
            color: bar.asking ? Theme.bg : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }
    }

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 34 }
        text: "drag a bubble to throw it   ·   into the black hole to end it   ·   wheel to zoom   ·   Esc to close"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        opacity: (win.pending < 0 && win.notice === "") ? 0.65 * win.dim : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }
}
