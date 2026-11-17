import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "widgets"

// TEMPORARY demo effect: lightning on Hyprland's window borders. A click-through layer over the windows traces each
// the focused window's border (when it is on this screen) with a live bolt (widgets/EdgeSpark.qml), flaring when
// focus moves to it. Only the focused window: every bolt costs CPU, and a full-screen layer has to repaint.
// Hyprland itself keeps drawing its normal border underneath. Off with `Theme.lightning = false`
// (`ipc call lightning off`); nothing runs while it is off.
PanelWindow {
    id: win

    readonly property bool on: Theme.lightning && Theme.windowLightning
    visible: on

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-desktop-window-sparks"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}

    property int borderSize: 3
    // one entry per visible window, updated in place (so each window keeps its own live bolt)
    ListModel { id: wins }
    function sync(list) {
        for (let i = wins.count - 1; i >= 0; i--) if (!list.some(w => w.addr === wins.get(i).addr)) wins.remove(i);
        for (const w of list) {
            let k = -1;
            for (let i = 0; i < wins.count; i++) if (wins.get(i).addr === w.addr) { k = i; break; }
            if (k < 0) wins.append(w);
            else {
                const o = wins.get(k);
                // moved without an event we hide on (e.g. the scrolling layout sliding its columns): hide and fade back
                if (Math.abs(o.x - w.x) > 2 || Math.abs(o.y - w.y) > 2 || Math.abs(o.w - w.w) > 2 || Math.abs(o.h - w.h) > 2) win.hideWhileMoving();
                for (const key of ["x", "y", "w", "h", "focused"]) if (o[key] !== w[key]) wins.setProperty(k, key, w[key]);
            }
        }
    }
    property string focusedAddr: ""

    // read the windows from hyprctl (on Hyprland events, debounced, plus a slow safety poll)
    Process {
        id: read
        command: ["sh", "-c", "hyprctl -j clients; printf '\\036'; hyprctl -j monitors; printf '\\036'; hyprctl -j activewindow; printf '\\036'; hyprctl -j getoption general:border_size"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\x1e");
                if (parts.length < 4) return;
                let clients = [], mons = [], act = {}, bs = 3;
                try { clients = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { return; }
                try { act = JSON.parse(parts[2]); } catch (e) { act = {}; }
                try { bs = JSON.parse(parts[3]).int || 3; } catch (e) {}
                const m = mons.find(x => x.name === win.screen?.name);
                if (!m) { win.sync([]); return; }
                const wsIds = [m.activeWorkspace?.id];
                if (m.specialWorkspace && m.specialWorkspace.id) wsIds.push(m.specialWorkspace.id);
                const fullscreen = clients.some(c => c.monitor === m.id && wsIds.includes(c.workspace?.id) && c.fullscreen > 0);
                const out = [];
                if (!fullscreen) for (const c of clients) {
                    if (!c.mapped || c.hidden || c.monitor !== m.id || !wsIds.includes(c.workspace?.id)) continue;
                    if (c.address !== act.address) continue;      // only the focused window (each bolt costs CPU)
                    out.push({ addr: c.address, x: (c.at[0] - m.x) / m.scale, y: (c.at[1] - m.y) / m.scale,
                               w: c.size[0] / m.scale, h: c.size[1] / m.scale, focused: c.address === act.address });
                }
                win.borderSize = bs;
                const prev = win.focusedAddr;
                win.focusedAddr = act.address || "";
                win.sync(out);
                if (prev !== win.focusedAddr) win.flare = win.focusedAddr;
            }
        }
    }
    property string flare: ""
    function refresh() { if (on && !read.running) read.running = true; else if (on) again.restart(); }
    Timer { id: again; interval: 120; onTriggered: win.refresh() }
    Timer { id: debounce; interval: 60; onTriggered: win.refresh() }
    Timer { interval: 700; repeat: true; running: win.on; onTriggered: win.refresh() }
    // Hyprland only reports where a window will END UP, not where it is mid-animation; so while windows open, move,
    // resize, switch workspace or the scrolling layout slides its columns, the bolts hide at once and fade back in after the animation (~420 ms) has landed.
    property real show: 1
    NumberAnimation { id: fadeIn; target: win; property: "show"; to: 1; duration: 220; easing.type: Easing.OutCubic }
    Timer { id: settle; interval: 460; onTriggered: fadeIn.restart() }
    function hideWhileMoving() { fadeIn.stop(); show = 0; settle.restart(); }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name;
            // activewindow too: in the scrolling layout, focusing another column slides every window (no move event)
            if (n.startsWith("openwindow") || n.startsWith("closewindow") || n.startsWith("movewindow") || n.startsWith("activewindow")
                || n === "workspace" || n === "workspacev2" || n.startsWith("changefloatingmode") || n.startsWith("fullscreen")
                || n.startsWith("activespecial") || n.startsWith("moveworkspace"))
                win.hideWhileMoving();
            if (n.startsWith("activewindow") || n.startsWith("openwindow") || n.startsWith("closewindow") || n.startsWith("movewindow")
                || n.startsWith("workspace") || n.startsWith("changefloatingmode") || n.startsWith("fullscreen")
                || n.startsWith("activespecial") || n.startsWith("resizewindow") || n === "configreloaded")
                debounce.restart();
        }
    }
    onOnChanged: if (on) refresh()
    Component.onCompleted: refresh()

    Repeater {
        model: wins
        EdgeSpark {
            id: ws
            required property var model
            readonly property var modelData: model
            anchors.fill: parent
            // on the middle of Hyprland's border, just outside the window
            readonly property real o: win.borderSize / 2 + 1
            points: [[modelData.x - o, modelData.y - o], [modelData.x + modelData.w + o, modelData.y - o],
                     [modelData.x + modelData.w + o, modelData.y + modelData.h + o], [modelData.x - o, modelData.y + modelData.h + o]]
            closed: true
            opacity: win.show
            cornerPin: 14
            intensity: modelData.focused ? 0.38 : 0.1
            step: 8
            speed: 0.7
            forks: modelData.focused
            Connections {
                target: win
                function onFlareChanged() { if (win.flare === ws.model.addr) ws.burst(0.25); }
            }
        }
    }
}
