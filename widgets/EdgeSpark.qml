import QtQuick
import QtQuick.Shapes
import ".."

// A border that IS lightning. The whole path (a ring, or an open/closed polyline) is drawn as one continuous
// crackling bolt: a fine, low jitter everywhere, plus a few "surges" (bell-shaped zones of much higher amplitude)
// that travel along it, so the edge reads as one live unit with bright knots running round. Two strands (a main
// bolt and a thinner one beside it), a wide soft glow underneath, a white-hot core on top, and short forks that
// flick off the surges. Re-rolled ~24 times a second.
//
//   intensity 0..1   resting energy (amplitude, number and size of surges, brightness)
//   burst(a)         flare up to `a` for a moment, settling back on its own
//   arcFrom/arcTo    draw only part of the path (fractions of its length), e.g. a gauge
//
//   EdgeSpark { anchors.fill: parent; ring: true; cx: 100; cy: 100; r: 90 }
//   EdgeSpark { anchors.fill: parent; points: [[0, 0], [w, 0], [w, h], [0, h]]; closed: true }
Shape {
    id: sp

    property bool ring: false
    property real cx: 0
    property real cy: 0
    property real r: 50
    property var points: []
    property bool closed: false
    property real arcFrom: 0
    property real arcTo: 1

    property real intensity: 0.3
    property color color: Theme.accent
    property color coreColor: Qt.rgba(1, 1, 1, 0.92)
    property bool running: visible
    property real speed: 1
    property real step: 6               // px between jitter points (bigger = cheaper, coarser)
    property bool forks: true
    property real cornerPin: 0          // > 0: the jitter fades to nothing within this many px of each corner, so
                                        // corners sit exactly on the shape (used for window borders)

    property real boost: 0
    readonly property real level: Math.min(1, intensity + boost)
    function burst(amount) { boost = Math.max(boost, amount === undefined ? 0.8 : amount); }

    // the default renderer, triangulated off the main thread (CurveRenderer is far too costly for jagged lines)
    asynchronous: true

    // ---- geometry ----
    property var segs: []
    property real total: 0
    function rebuild() {
        if (ring) { total = 2 * Math.PI * r; return; }
        const pts = closed && points.length > 1 ? points.concat([points[0]]) : points;
        const out = [];
        let acc = 0;
        for (let i = 1; i < pts.length; i++) {
            const a = pts[i - 1], b = pts[i], len = Math.hypot(b[0] - a[0], b[1] - a[1]);
            if (len < 0.001) continue;
            out.push({ a: a, b: b, len: len, at: acc });
            acc += len;
        }
        segs = out;
        total = acc;
    }
    onPointsChanged: rebuild()
    onRChanged: rebuild()
    onRingChanged: rebuild()
    onClosedChanged: rebuild()
    Component.onCompleted: rebuild()

    // point and unit normal at fraction u of the whole path
    function at(u) {
        if (ring) {
            const a = u * 2 * Math.PI - Math.PI / 2;
            const c = Math.cos(a), s = Math.sin(a);
            return [cx + c * r, cy + s * r, c, s];
        }
        if (segs.length === 0) return [0, 0, 0, -1];
        const d = Math.max(0, Math.min(total, u * total));
        let k = 0;
        while (k < segs.length - 1 && segs[k].at + segs[k].len < d) k++;
        const S = segs[k], f = (d - S.at) / S.len;
        const dx = (S.b[0] - S.a[0]) / S.len, dy = (S.b[1] - S.a[1]) / S.len;
        return [S.a[0] + (S.b[0] - S.a[0]) * f, S.a[1] + (S.b[1] - S.a[1]) * f, dy, -dx];
    }

    // ---- surges: zones of high amplitude that travel along the path ----
    property var surges: []
    property real clock: 0
    property string glowPath: "M0,0"
    property string mainPath: "M0,0"
    property string thinPath: "M0,0"
    property string forkPath: "M0,0"

    function tick(dt) {
        clock += dt;
        boost = Math.max(0, boost - dt * 1.1);
        const L = level;
        const span = arcTo - arcFrom;
        const len = Math.max(1, total * span);
        if (len < 4) { mainPath = thinPath = glowPath = forkPath = "M0,0"; return; }
        const loop = (ring || closed) && span > 0.999;

        // keep 1..4 surges (more with energy), each with its own speed, width and life
        const want = 1 + Math.round(L * L * 3);
        let ss = surges.filter(q => q.life > 0);
        while (ss.length < want)
            ss.push({ c: Math.random(), v: (0.06 + Math.random() * 0.16) * (Math.random() < 0.5 ? -1 : 1),
                      w: (40 + Math.random() * 70) / len, a: 0.6 + Math.random() * 0.4, life: 0.8 + Math.random() * 2.2, age: 0 });
        for (const q of ss) {
            q.c += q.v * dt * speed * Math.min(3, 700 / len) * (1 + L);
            if (loop) q.c = ((q.c % 1) + 1) % 1;
            q.life -= dt; q.age += dt;
        }
        surges = ss;

        const n = Math.max(8, Math.min(180, Math.round(len / step)));
        // energy is felt quadratically: low levels stay a calm, fine crackle; only high levels (a notification,
        // a flare) get the big surges
        const base = 0.35 + 1.4 * L;                      // the fine crackle everywhere
        const peak = 1.5 + 16 * L * L;                    // the surges
        let m = "", t = "", f = "";
        // where to sample (0..1 along the drawn part): evenly spaced, but every corner of a polyline is always one of
        // the samples, so corners stay sharp and exact instead of being cut across
        const gs = [];
        if (ring) { for (let i = 0; i <= n; i++) gs.push(i / n); }
        else {
            const d0 = arcFrom * total, d1 = arcTo * total;
            const marks = [d0];
            for (const S of segs) if (S.at > d0 + 0.5 && S.at < d1 - 0.5) marks.push(S.at);
            marks.push(d1);
            const per = Math.max(2, (d1 - d0) / n);
            for (let k = 1; k < marks.length; k++) {
                const a = marks[k - 1], b = marks[k], cnt = Math.max(1, Math.round((b - a) / per));
                for (let i = (k === 1 ? 0 : 1); i <= cnt; i++) gs.push(((a + (b - a) * i / cnt) - d0) / Math.max(1, d1 - d0));
            }
        }
        const last = gs.length - 1;
        for (let i = 0; i <= last; i++) {
            const g = gs[i];                              // 0..1 along the drawn part
            const p = at(arcFrom + span * g);
            let env = 0;
            for (const q of ss) {
                let d = Math.abs(g - q.c);
                if (loop) d = Math.min(d, 1 - d);
                const fade = Math.min(1, q.age * 3, q.life * 2);
                env += q.a * fade * Math.exp(-(d * d) / (q.w * q.w));
            }
            // ends of an open path stay pinned to it
            let pin = loop ? 1 : Math.min(1, g * n / 3, (1 - g) * n / 3);
            if (cornerPin > 0 && !ring) {
                const dpx = (arcFrom + span * g) * total;
                let near = Math.min(dpx, total - dpx);
                for (const S of segs) near = Math.min(near, Math.abs(dpx - S.at));
                pin = Math.min(pin, near / cornerPin);
            }
            const amp = (base + peak * Math.min(1.4, env)) * pin;
            const j1 = (Math.random() * 2 - 1) * amp;
            const j2 = (Math.random() * 2 - 1) * amp * 0.7;
            const x1 = p[0] + p[2] * j1, y1 = p[1] + p[3] * j1;
            m += (i === 0 ? "M" : " L") + x1.toFixed(1) + "," + y1.toFixed(1);
            if (L > 0.3) t += (i === 0 ? "M" : " L") + (p[0] + p[2] * j2).toFixed(1) + "," + (p[1] + p[3] * j2).toFixed(1);
            // forks: now and then a short branch flicks outward from a surge
            if (forks && L > 0.45 && env > 0.55 && Math.random() < 0.1 * L) {
                const dir = Math.random() < 0.5 ? 1 : -1;
                let fx = x1, fy = y1;
                f += " M" + fx.toFixed(1) + "," + fy.toFixed(1);
                const segsN = 3 + Math.floor(Math.random() * 3);
                const tx = -p[3], ty = p[2];
                for (let k = 0; k < segsN; k++) {
                    const out = (4 + Math.random() * 6) * (1 + L);
                    const side = (Math.random() * 2 - 1) * 6;
                    fx += p[2] * out * dir + tx * side; fy += p[3] * out * dir + ty * side;
                    f += " L" + fx.toFixed(1) + "," + fy.toFixed(1);
                }
            }
        }
        if (loop) { m += " Z"; if (t !== "") t += " Z"; }
        mainPath = m;
        thinPath = t === "" ? "M0,0" : t;
        glowPath = m;
        forkPath = f === "" ? "M0,0" : f;
    }
    // driven by the shared clock in Theme (25 Hz); at rest only every other tick
    readonly property bool live: sp.running && sp.visible && sp.total > 0
    onLiveChanged: Theme.sparkUsers += live ? 1 : -1
    Component.onDestruction: if (live) Theme.sparkUsers -= 1
    Connections {
        target: Theme
        enabled: sp.live
        function onSparkTickChanged() {
            sp.tick(0.04);
        }
    }

    // flicker: brightness breathes a little, more with energy
    property real flick: 1
    Timer { interval: 90; repeat: true; running: sp.running && sp.visible; onTriggered: sp.flick = 0.82 + Math.random() * 0.18 }

    ShapePath {      // wide soft glow
        strokeColor: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, (0.06 + 0.22 * sp.level * sp.level) * sp.flick)
        strokeWidth: 4 + 9 * sp.level * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.BevelJoin
        PathSvg { path: sp.glowPath }
    }
    ShapePath {      // second, thinner strand (only while there is energy to spare)
        strokeColor: sp.level > 0.3 ? Qt.rgba(sp.color.r, sp.color.g, sp.color.b, (0.35 + 0.3 * sp.level) * sp.flick) : "transparent"
        strokeWidth: 0.8
        fillColor: "transparent"
        joinStyle: ShapePath.BevelJoin
        PathSvg { path: sp.thinPath }
    }
    ShapePath {      // main bolt in the accent colour
        strokeColor: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, (0.6 + 0.3 * sp.level) * sp.flick)
        strokeWidth: 1.3 + 1.8 * sp.level * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.BevelJoin
        PathSvg { path: sp.mainPath }
    }
    ShapePath {      // white-hot core
        strokeColor: Qt.rgba(sp.coreColor.r, sp.coreColor.g, sp.coreColor.b, (0.25 + 0.7 * sp.level * sp.level) * sp.flick)
        strokeWidth: 0.7 + 0.6 * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.BevelJoin
        PathSvg { path: sp.mainPath }
    }
    ShapePath {      // forks
        strokeColor: Qt.rgba(sp.coreColor.r, sp.coreColor.g, sp.coreColor.b, 0.7 * sp.flick)
        strokeWidth: 0.9
        fillColor: "transparent"
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.BevelJoin
        PathSvg { path: sp.forkPath }
    }
}
