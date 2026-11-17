import QtQuick
import QtQuick.Shapes
import ".."

// Lightning that lives on an edge: short crackling sparks run along a ring or an open/closed polyline, so a border
// looks electrified. Subtle at rest (a couple of thin, faint runners); `intensity` (0..1) makes more, brighter,
// wider-jittered runners. `burst()` flares it up for a moment and lets it settle back.
// Each runner is a short stretch of the path, re-drawn with fresh sideways jitter ~30 times a second (tapered at
// both ends), as a soft glow under a thin bright core.
//
//   EdgeSpark { anchors.fill: parent; ring: true; cx: 100; cy: 100; r: 90 }              // around a circle
//   EdgeSpark { anchors.fill: parent; points: [[0, 10], [500, 10]] }                     // along a line
//   EdgeSpark { ...; arcFrom: 0; arcTo: 0.6 }                                            // only part of the path
Shape {
    id: sp

    property bool ring: false
    property real cx: 0
    property real cy: 0
    property real r: 50
    property var points: []            // polyline [[x, y], ...] when not a ring
    property bool closed: false        // polyline joins back to its start
    property real arcFrom: 0           // part of the path to use, as fractions of its length
    property real arcTo: 1

    property real intensity: 0.25      // resting level
    property color color: Theme.accent
    property color coreColor: Qt.rgba(1, 1, 1, 0.9)
    property bool running: visible
    property real speed: 1             // how fast the runners travel

    property real boost: 0             // added by burst(), decays
    readonly property real level: Math.min(1, intensity + boost)
    function burst(amount) { boost = Math.max(boost, amount === undefined ? 0.8 : amount); }

    preferredRendererType: Shape.CurveRenderer

    // ---- geometry: a point (and its outward normal) at fraction u of the path ----
    property var segs: []
    property real total: 0
    function rebuild() {
        if (ring) { total = 2 * Math.PI * r; return; }
        const pts = closed && points.length > 1 ? points.concat([points[0]]) : points;
        const out = [];
        let acc = 0;
        for (let i = 1; i < pts.length; i++) {
            const a = pts[i - 1], b = pts[i], len = Math.hypot(b[0] - a[0], b[1] - a[1]);
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
        const S = segs[k], f = S.len > 0 ? (d - S.at) / S.len : 0;
        const dx = (S.b[0] - S.a[0]) / (S.len || 1), dy = (S.b[1] - S.a[1]) / (S.len || 1);
        return [S.a[0] + (S.b[0] - S.a[0]) * f, S.a[1] + (S.b[1] - S.a[1]) * f, dy, -dx];
    }

    // ---- runners ----
    property var runners: []
    property string glowPath: "M0,0"
    property string corePath: "M0,0"
    property int frame: 0

    function wrapU(u) {
        const span = arcTo - arcFrom;
        if (ring || closed) return arcFrom + (((u - arcFrom) % span) + span) % span;
        return u;
    }
    function tick(dt) {
        boost = Math.max(0, boost - dt * 1.3);
        const L = level;
        const want = 1 + Math.round(L * 4);
        const rs = runners.filter(q => q.life > 0);
        while (rs.length < want) {
            rs.push({ u: arcFrom + Math.random() * (arcTo - arcFrom), len: 0.03 + Math.random() * 0.05,
                      v: (0.05 + Math.random() * 0.12) * (Math.random() < 0.5 ? -1 : 1),
                      life: 0.5 + Math.random() * 1.4 });
        }
        let core = "", glow = "";
        const span = arcTo - arcFrom;
        const pxLen = Math.max(1, total * span);
        for (const q of rs) {
            q.life -= dt;
            q.u += q.v * dt * speed * (1 + L * 1.5) * Math.min(4, 900 / pxLen);
            if (!(ring || closed) && (q.u < arcFrom || q.u > arcTo)) { q.life = 0; continue; }
            const segLen = q.len * (0.6 + L * 0.9) * Math.min(1, 600 / pxLen) * span;
            const n = Math.max(5, Math.round(segLen * total / 7));
            const amp = 1.2 + 5.5 * L;
            let d = "";
            for (let i = 0; i <= n; i++) {
                const f = i / n;
                let u = q.u + segLen * (f - 0.5);
                u = wrapU(u);
                if (!(ring || closed) && (u < arcFrom || u > arcTo)) continue;
                const p = at(u);
                const taper = Math.sin(Math.PI * f);
                const j = (Math.random() * 2 - 1) * amp * taper;
                d += (d === "" ? "M" : " L") + (p[0] + p[2] * j).toFixed(1) + "," + (p[1] + p[3] * j).toFixed(1);
            }
            if (d !== "") { core += d + " "; glow += d + " "; }
        }
        runners = rs;
        corePath = core || "M0,0";
        glowPath = glow || "M0,0";
    }
    FrameAnimation {
        running: sp.running && sp.visible && sp.total > 0
        onTriggered: { if (++sp.frame % 2 === 0) sp.tick(Math.min(0.08, frameTime * 2)); }
    }

    opacity: 0.45 + 0.55 * level
    ShapePath {
        strokeColor: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, 0.16 + 0.22 * sp.level)
        strokeWidth: 3 + 6 * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: sp.glowPath }
    }
    ShapePath {
        strokeColor: Qt.rgba(sp.color.r, sp.color.g, sp.color.b, 0.7)
        strokeWidth: 1.6 + 1.2 * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: sp.corePath }
    }
    ShapePath {
        strokeColor: sp.coreColor
        strokeWidth: 0.6 + 0.6 * sp.level
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: sp.corePath }
    }
}
