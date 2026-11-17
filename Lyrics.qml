pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// Synced lyrics for whatever is playing, looked up the way skwd's daemon does it (MIT, liixini/skwd-daemon):
//   1. Musixmatch "richsync" - lyrics with real per-WORD timing (what drives the word highlight)
//   2. Musixmatch line-synced lyrics
//   3. LRCLIB (lrclib.net), exact lookup then search - line-synced only
// Musixmatch is reached through its desktop-app endpoint with an anonymous token, like skwd does (it is an
// unofficial interface). As of writing, that endpoint hands out a null token and answers richsync requests
// with 404, so it is OFF by default (`musixmatch`): word timing from it is not obtainable right now.
// Word timing is only ever real data (Musixmatch richsync, or enhanced LRC with <mm:ss.xx> word tags);
// when a track has none, the whole line is lit at once and nothing is estimated.
// Only the artist and title (and the track length) of what is playing are sent. Results are cached in
// memory for the session. Set `enabled` to false to switch it all off.
Singleton {
    id: root

    property bool enabled: true
    property bool musixmatch: false     // try Musixmatch first (word timing when it works); see above

    readonly property var player: Audio.player
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string title: player?.trackTitle ?? ""
    readonly property real duration: player?.lengthSupported ? (player.length ?? 0) : 0   // seconds
    readonly property string key: (artist + "\u0001" + title)

    // "idle" (nothing playing) | "loading" | "none" (nothing found) | "ready"
    property string status: "idle"
    property string source: ""          // where the current lyrics came from
    property bool wordSynced: false     // true when the lines carry real word timing
    property var lines: []              // [{ t, end, text, words: [{ w, s, e }] | null }], sorted by time
    property int index: -1              // current line, -1 before the first
    property int wordIndex: -1          // current word within that line (-1 before the first)
    property real positionMs: 0

    readonly property bool hasLyrics: status === "ready" && lines.length > 0
    readonly property string line: hasLyrics && index >= 0 ? lines[index].text : ""
    readonly property string next: hasLyrics && index + 1 < lines.length ? lines[index + 1].text : ""

    // The current line as styled text for a Text item (textFormat: Text.StyledText). With word timing, words
    // already sung are in the accent colour and the rest dimmer; without it, the whole line is lit.
    function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function buildHtml(idx, wi, sung, rest) {
        if (!hasLyrics || idx < 0) return "";
        const L = lines[idx];
        if (!L.words || L.words.length === 0) return "<font color=\"" + sung + "\">" + esc(L.text) + "</font>";
        let out = "";
        for (let i = 0; i < L.words.length; i++)
            out += (i > 0 ? " " : "") + "<font color=\"" + (i <= wi ? sung : rest) + "\">" + esc(L.words[i].w) + "</font>";
        return out;
    }
    readonly property string lineHtml: buildHtml(index, wordIndex, String(Theme.accent), String(Theme.fgDim))

    property var cache: ({})
    property string wanted: ""

    // ================================================================= fetching
    onKeyChanged: reset()
    onEnabledChanged: reset()
    Component.onCompleted: reset()

    function stopAll() {
        tokenProc.running = false; mxSearchProc.running = false; mxRichProc.running = false;
        mxSubProc.running = false; lrcGetProc.running = false; lrcSearchProc.running = false;
    }

    function reset() {
        stopAll();
        lines = []; index = -1; wordIndex = -1; wordSynced = false; source = "";
        if (!enabled || !player || title === "") { status = "idle"; return; }
        const hit = cache[key];
        if (hit !== undefined) { apply(hit.lines, hit.source); return; }
        status = "loading";
        wanted = key;
        if (musixmatch) mxStart(); else lrcStart();
    }

    function apply(parsed, src) {
        lines = parsed;
        source = src;
        wordSynced = parsed.some(l => l.words && l.words.length > 0);
        status = parsed.length > 0 ? "ready" : "none";
        update();
    }

    function finish(forKey, parsed, src) {
        if (forKey !== wanted) return;                       // the song changed meanwhile
        const c = cache; c[forKey] = { lines: parsed, source: src }; cache = c;
        apply(parsed, src);
    }

    readonly property string ua: "skwd-lyrics/1.0"
    function curl(proc, url, params) {
        const cmd = ["curl", "-sG", "--max-time", "10", "-A", ua, url];
        for (const k in params) cmd.push("--data-urlencode", k + "=" + params[k]);
        proc.command = cmd;
        proc.running = true;
    }
    function json(text) { try { return JSON.parse(text); } catch (e) { return null; } }

    // ---- Musixmatch ----
    readonly property string mxBase: "https://apic-desktop.musixmatch.com/ws/1.1"
    property string mxToken: ""
    property real mxTokenAt: 0
    property string mxTrackId: ""

    function mxParams(extra) {
        const p = Object.assign({}, extra);
        p.app_id = "web-desktop-app-v1.0";
        p.usertoken = mxToken;
        p.t = String(Date.now());
        return p;
    }
    function mxBody(j) {
        if (!j || !j.message || !j.message.header || j.message.header.status_code !== 200) return null;
        return j.message.body ?? null;
    }

    function mxStart() {
        if (mxToken !== "" && Date.now() - mxTokenAt < 600000) { mxSearch(); return; }
        curl(tokenProc, mxBase + "/token.get", { app_id: "web-desktop-app-v1.0", user_language: "en" });
    }
    Process {
        id: tokenProc
        stdout: StdioCollector {
            onStreamFinished: {
                const forKey = root.wanted;
                if (forKey !== root.key) return;
                const b = root.mxBody(root.json(text));
                if (b && b.user_token) { root.mxToken = b.user_token; root.mxTokenAt = Date.now(); root.mxSearch(); }
                else root.lrcStart();
            }
        }
    }

    function mxSearch() {
        curl(mxSearchProc, mxBase + "/track.search", mxParams({ q: artist + " " + title, page_size: "5", page: "1" }));
    }
    Process {
        id: mxSearchProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.wanted !== root.key) return;
                const b = root.mxBody(root.json(text));
                const id = b && b.track_list ? root.mxBestMatch(b.track_list) : null;
                if (id === null) { root.lrcStart(); return; }
                root.mxTrackId = String(id);
                root.curl(mxRichProc, root.mxBase + "/track.richsync.get", root.mxParams({ track_id: root.mxTrackId }));
            }
        }
    }

    readonly property var stop: ["the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "by", "for", "with", "from",
        "is", "it", "i", "im", "you", "me", "my", "feat", "ft", "featuring", "vs", "remix", "edit", "version",
        "remastered", "remaster", "mix", "official", "video", "audio"]
    function tokens(s) {
        return s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").split(" ").filter(w => w.length > 1 && stop.indexOf(w) < 0);
    }
    function overlap(a, b) { return a.filter(t => b.indexOf(t) >= 0).length; }
    // same scoring as skwd: artist overlap counts double, and both artist and title must share a word
    function mxBestMatch(list) {
        const ta = tokens(artist), tt = tokens(title);
        let best = null, bestScore = 0;
        for (const item of list) {
            const tr = item.track;
            if (!tr) continue;
            const ao = overlap(ta, tokens(tr.artist_name ?? "")), to = overlap(tt, tokens(tr.track_name ?? ""));
            if (ta.length > 0 && ao === 0) continue;
            if (tt.length > 0 && to === 0) continue;
            const score = ao * 2 + to;
            if (score > bestScore) { bestScore = score; best = tr.track_id; }
        }
        return best;
    }

    Process {
        id: mxRichProc
        stdout: StdioCollector {
            onStreamFinished: {
                const forKey = root.wanted;
                if (forKey !== root.key) return;
                const b = root.mxBody(root.json(text));
                let parsed = [];
                try {
                    if (b && b.richsync && b.richsync.richsync_body) parsed = root.parseRichsync(JSON.parse(b.richsync.richsync_body));
                } catch (e) {}
                if (parsed.length > 0) { root.finish(forKey, parsed, "Musixmatch (word-synced)"); return; }
                root.curl(mxSubProc, root.mxBase + "/track.subtitle.get", root.mxParams({ track_id: root.mxTrackId, subtitle_format: "lrc" }));
            }
        }
    }
    Process {
        id: mxSubProc
        stdout: StdioCollector {
            onStreamFinished: {
                const forKey = root.wanted;
                if (forKey !== root.key) return;
                const b = root.mxBody(root.json(text));
                const parsed = b && b.subtitle && b.subtitle.subtitle_body ? root.parseLrc(b.subtitle.subtitle_body) : [];
                if (parsed.length > 0) root.finish(forKey, parsed, "Musixmatch");
                else root.lrcStart();
            }
        }
    }

    // ---- LRCLIB ----
    function lrcStart() {
        const p = { artist_name: artist, track_name: title };
        if (duration > 0) p.duration = String(Math.round(duration));
        curl(lrcGetProc, "https://lrclib.net/api/get", p);
    }
    Process {
        id: lrcGetProc
        stdout: StdioCollector {
            onStreamFinished: {
                const forKey = root.wanted;
                if (forKey !== root.key) return;
                const j = root.json(text);
                const parsed = j && j.syncedLyrics ? root.parseLrc(j.syncedLyrics) : [];
                if (parsed.length > 0) { root.finish(forKey, parsed, "LRCLIB"); return; }
                root.curl(lrcSearchProc, "https://lrclib.net/api/search", { q: root.artist + " " + root.title });
            }
        }
    }
    Process {
        id: lrcSearchProc
        stdout: StdioCollector {
            onStreamFinished: {
                const forKey = root.wanted;
                if (forKey !== root.key) return;
                let parsed = [];
                const arr = root.json(text);
                if (Array.isArray(arr)) {
                    let best = null, bestDelta = 1e9;
                    for (const it of arr) {
                        if (!it.syncedLyrics) continue;
                        const delta = root.duration > 0 && it.duration ? Math.abs(it.duration - root.duration) : 0;
                        if (delta < bestDelta) { best = it; bestDelta = delta; }
                    }
                    if (best) parsed = root.parseLrc(best.syncedLyrics);
                }
                root.finish(forKey, parsed, "LRCLIB");
            }
        }
    }

    // ---- parsers ----
    // Musixmatch richsync: [{ ts, te, x: "full line", l: [{ c: "word", o: offsetSeconds }, ...] }, ...]
    // (the same layout skwd parses): word i starts at ts + o_i and ends where the next word starts.
    function parseRichsync(data) {
        const out = [];
        for (const ln of data) {
            const ts = Number(ln.ts ?? 0), te = Number(ln.te ?? 0);
            const words = [];
            let full = "";
            for (const f of (ln.l ?? [])) {
                const c = f.c ?? "";
                full += c;
                if (c.trim() === "") continue;
                const s = Math.round((ts + Number(f.o ?? 0)) * 1000);
                words.push({ w: c.trim(), s: s, e: s });
            }
            for (let i = 0; i + 1 < words.length; i++) words[i].e = words[i + 1].s;
            if (words.length > 0) words[words.length - 1].e = Math.round(te * 1000);
            const text = (ln.x ?? full).trim();
            if (text !== "") out.push({ t: Math.round(ts * 1000), end: Math.round(te * 1000), text: text, words: words });
        }
        out.sort((a, b) => a.t - b.t);
        return out;
    }

    // Plain LRC: "[01:23.45] text" (one or more timestamps per line); line timing only.
    function parseLrc(lrc) {
        const out = [];
        for (const raw of lrc.split("\n")) {
            const stamps = [];
            let rest = raw, m;
            while ((m = /^\s*\[(\d+):(\d+(?:\.\d+)?)\]/.exec(rest)) !== null) {
                stamps.push((Number(m[1]) * 60 + Number(m[2])) * 1000);
                rest = rest.slice(m[0].length);
            }
            if (stamps.length === 0) continue;

            // enhanced LRC: "<01:23.45>word" tags carry real word timing
            let words = null;
            if (/<\d+:\d+(?:\.\d+)?>/.test(rest)) {
                words = [];
                const re = /<(\d+):(\d+(?:\.\d+)?)>([^<]*)/g;
                let w;
                while ((w = re.exec(rest)) !== null) {
                    const s0 = Math.round((Number(w[1]) * 60 + Number(w[2])) * 1000);
                    for (const part of w[3].trim().split(/\s+/).filter(x => x !== "")) words.push({ w: part, s: s0, e: s0 });
                }
            }
            const text = rest.replace(/<\d+:\d+(?:\.\d+)?>/g, "").replace(/\s+/g, " ").trim();
            for (const t of stamps) out.push({ t: t, end: 0, text: text, words: words ? words.map(x => ({ w: x.w, s: x.s, e: x.e })) : null });
        }
        out.sort((a, b) => a.t - b.t);
        // a word ends where the next one starts; the last one where the next line starts
        for (let i = 0; i < out.length; i++) {
            const ws = out[i].words;
            if (!ws || ws.length === 0) continue;
            for (let k = 0; k < ws.length; k++) ws[k].e = k + 1 < ws.length ? ws[k + 1].s : (i + 1 < out.length ? out[i + 1].t : ws[k].s + 1000);
        }
        return out;
    }

    // ================================================================= following the song
    function update() {
        if (!hasLyrics) { index = -1; wordIndex = -1; return; }
        const p = positionMs;
        let lo = 0, hi = lines.length - 1, ans = -1;          // last line whose start <= position
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lines[mid].t <= p) { ans = mid; lo = mid + 1; } else hi = mid - 1;
        }
        if (ans !== index) index = ans;
        let wi = -1;
        if (ans >= 0 && lines[ans].words) {
            const ws = lines[ans].words;
            for (let i = 0; i < ws.length; i++) { if (ws[i].s <= p) wi = i; else break; }
        }
        if (wi !== wordIndex) wordIndex = wi;
    }

    // The player's position is read once a second; in between, a local clock keeps time so the word
    // highlight moves smoothly without polling the player every few milliseconds.
    property real basePos: 0
    property real baseAt: Date.now()
    function resync() {
        if (!player) return;
        basePos = (player.position ?? 0) * 1000;
        baseAt = Date.now();
        positionMs = basePos;
        update();
    }
    readonly property bool running: enabled && hasLyrics && player !== null && player.isPlaying
    onRunningChanged: resync()

    Timer {
        interval: 50
        repeat: true
        running: root.running
        onTriggered: { root.positionMs = root.basePos + (Date.now() - root.baseAt); root.update(); }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: { if (root.player) { root.player.positionChanged(); root.resync(); } }
    }
    Connections {
        target: root.player
        function onPositionChanged() { root.resync(); }
    }
}
