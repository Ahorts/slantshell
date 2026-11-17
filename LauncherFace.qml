import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import "widgets"

// App Switcher & Command Centre (Borderless center-screen overlay — NO generic rectangular container box!):
//   - Left stage (Window Switcher Wheel): RediWM-style 360° analytic circular sector wheel (`640x640`) dedicated
//     to your open Hyprland windows (or top apps when no windows are open). Has its OWN independent selection
//     (`wheelSel`) and unwrapped shortest-path ring angle (`turnDeg`), so wrapping from the last sector
//     to the first steps smoothly forward across 12 o'clock instead of spinning backwards!
//   - Right stage (App & Command Stream): independent scrollable list (`listSel`) so scrolling through installed
//     apps never turns the radial window wheel on the left.
//   - Top stage: floating pill search bar with prefix modes (`@` windows, `>` actions, inline math calculator).
PanelWindow {
    id: win

    property bool open: false
    property var onlyWs: []                  // when not empty: only windows on these workspaces (used for recordings)
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    property real openProg: wanted ? 1 : 0
    Behavior on openProg { NumberAnimation { duration: win.wanted ? 260 : 140; easing.type: Easing.OutCubic } }
    // Opening: the hub (with the live preview) pops first, then the sectors unfold clockwise from 12 o'clock, each
    // growing outward as the sweep passes it, with the lightning rim drawing itself round alongside.
    property real sweep: 0
    NumberAnimation { id: sweepIn; target: win; property: "sweep"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
    // satellite i flies out of the core as the opening sweep passes it (staggered)
    function sectorGrow(i, n) { const a = (i / Math.max(1, n)) * 0.55; return sm(a, a + 0.45, sweep); }

    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    // The surface stays mapped on its screen all the time (empty and click-through while closed), so opening is
    // instant instead of waiting for the compositor to create a new layer surface.
    readonly property bool busy: wanted || dim > 0.004 || openProg > 0.004
    visible: true
    mask: Region { item: win.busy ? fullMask : null }
    Item { id: fullMask; anchors.fill: parent }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-launcher"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    property string mode: "all"

    // Two scenes: the window SWITCHER (the wheel, centre stage) and SEARCH (search bar + list). Typing, Down or the
    // Apps/Actions chips go to search; Esc / Tab on an empty search (or the Windows chip) come back. Between them the
    // wheel spins, shrinks and flies into the search bar's lens (and back out of it), the bar unrolls from the lens,
    // and the list cascades in; a burst of lightning runs round the wheel's rim on each change.
    property bool forceSearch: false
    readonly property bool searching: openWindows.length === 0 || forceSearch || input.text !== "" || mode !== "all"
    property real searchP: searching ? 1 : 0
    Behavior on searchP { enabled: win.sceneAnim; SpringAnimation { spring: 3.6; damping: 0.5; epsilon: 0.002 } }
    // the scene change only animates once the switcher is open (on opening it starts in the right scene at once)
    property bool sceneAnim: false
    Timer { id: sceneAnimOn; interval: 200; onTriggered: win.sceneAnim = true }
    function sm(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
    onSearchingChanged: {
        activeFocusStage = searching ? "list" : "wheel";

    }
    function toSwitcher() { forceSearch = false; mode = "all"; input.text = ""; }
    // Which stage Enter activates: "wheel" or "list"
    property string activeFocusStage: "wheel"
    property int wheelSel: 0
    property int listSel: 0
    readonly property int maxWheelSlots: 8

    readonly property var sysActions: [
        { kind: "action", title: "System Galaxy",       sub: "Open Gargantua process monitor",       icon: "", glyph: "󰇄", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "galaxy", "toggle"] },
        { kind: "action", title: "Wallpaper Switcher",  sub: "Open film-strip & gear dial picker",   icon: "", glyph: "󰸉", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "wallpapers", "toggle"] },
        { kind: "action", title: "Power Cascade",       sub: "Lock, log out, restart, or shut down", icon: "", glyph: "󰐥", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "power", "toggle"] },
        { kind: "action", title: "Wi-Fi & Bluetooth",   sub: "Open connectivity constellation",      icon: "", glyph: "󰤨", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "connectivity", "toggle"] },
        { kind: "action", title: "Toggle Hard Corners", sub: "Switch square vs rounded windows",     icon: "", glyph: "󰙀", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "sharp", "toggle"] },
        { kind: "action", title: "Shard Colour Wipe",   sub: "Trigger diagonal palette wipe",        icon: "", glyph: "󰔎", cmd: ["qs", "-p", "/home/ahorts/Documents/Projects/claude-demo/qs-desktop", "ipc", "call", "wipe", "test"] },
        { kind: "action", title: "Lock Session",        sub: "Lock the screen",                      icon: "", glyph: "󰌾", cmd: ["qs", "-p", Quickshell.shellPath("shell.qml"), "ipc", "call", "lock", "lock"] },
        { kind: "action", title: "Reload Hyprland",     sub: "Run hyprctl reload",                   icon: "", glyph: "󰑓", cmd: ["hyprctl", "reload"] }
    ]

    readonly property string calcResult: {
        const raw = input.text.trim();
        if (raw === "" || win.mode !== "all") return "";
        const expr = raw.startsWith("=") ? raw.slice(1).trim() : raw;
        if (!/^[0-9+\-*/().%\s^]+$/.test(expr) || !/[+\-*/%^]/.test(expr) || !/\d/.test(expr)) return "";
        try {
            const jsExpr = expr.replace(/\^/g, "**");
            const val = Function("\"use strict\"; return (" + jsExpr + ");")();
            if (typeof val === "number" && isFinite(val)) {
                return Number.isInteger(val) ? String(val) : Number(val.toFixed(6)).toString();
            }
        } catch (e) {}
        return "";
    }

    function score(item, q) {
        const name = item.title.toLowerCase();
        if (name.startsWith(q)) return 0;
        if (name.includes(" " + q)) return 1;
        if (name.includes(q)) return 2;
        if (item.extra.includes(q)) return 3;
        return -1;
    }

    // Open Hyprland windows (feeds the 360° Radial Window Switcher Wheel)
    readonly property var openWindows: {
        if (!wanted) return [];
        const winList = [];
        const appCounts = {};
        for (const t of ToplevelManager.toplevels.values) {
            const aid = t.appId || "window";
            appCounts[aid] = (appCounts[aid] || 0) + 1;
        }
        const appSeen = {};
        for (const t of ToplevelManager.toplevels.values) {
            const aid = t.appId || "window";
            appSeen[aid] = (appSeen[aid] || 0) + 1;
            const entry = DesktopEntries.heuristicLookup(aid);
            let ws = "";
            for (const h of Hyprland.toplevels.values) if (h.wayland === t) { ws = h.workspace ? String(h.workspace.name || h.workspace.id) : ""; break; }
            if (win.onlyWs.length > 0 && !win.onlyWs.includes(ws)) continue;
            winList.push({
                app: entry ? entry.name : aid,
                ws: ws,
                kind: "window",
                title: t.title || aid,
                sub: (entry ? entry.name : aid) + (appCounts[aid] > 1 ? "  ·  " + appSeen[aid] + "/" + appCounts[aid] : "  ·  Active Window"),
                extra: (aid + " " + (t.title || "")).toLowerCase(),
                icon: entry ? entry.icon : aid,
                glyph: "󰖯",
                stackCount: appCounts[aid] || 1,
                ref: t
            });
        }
        return winList;
    }

    // For demos: where (screen coordinates "x,y") the nearest pill sits whose window is on ANOTHER workspace than the
    // focused one ("" if none), so a scripted click shows the switch to another workspace.
    function pillOnOtherWs() {
        if (!wanted) return "";
        const cur = String(Hyprland.focusedMonitor?.activeWorkspace?.name ?? "");
        const items = wheelItems, n = items.length;
        let best = -1, bestD = 1e9;
        for (let i = 0; i < n; i++) {
            if (items[i].kind !== "window" || items[i].ws === "" || items[i].ws === cur) continue;
            const d = Math.min(Math.abs(i - wheelSel), n - Math.abs(i - wheelSel));
            if (d > 0 && d < bestD) { best = i; bestD = d; }
        }
        if (best < 0) return "";
        const p = wheelStage.satPos(best, 1);
        const g = wheelStage.mapToItem(null, p.x, p.y);
        return Math.round(g.x) + "," + Math.round(g.y);
    }

    // Right-hand scrollable stream items (Applications, Windows, or Actions)
    readonly property var listItems: {
        // built only when the search scene is used (building hundreds of app rows on open made it lag)
        if (!wanted || (!searching && openWindows.length > 0)) return [];
        const q = input.text.trim().toLowerCase();

        if (win.mode === "win") {
            if (q === "") return openWindows;
            return openWindows
                .map(i => ({ i: i, s: score(i, q) }))
                .filter(x => x.s >= 0)
                .sort((a, b) => a.s - b.s)
                .map(x => x.i);
        }

        if (win.mode === "act") {
            const acts = sysActions.map(a => Object.assign({ extra: (a.title + " " + a.sub).toLowerCase(), stackCount: 1 }, a));
            if (q === "") return acts;
            return acts
                .map(i => ({ i: i, s: score(i, q) }))
                .filter(x => x.s >= 0)
                .sort((a, b) => a.s - b.s)
                .map(x => x.i);
        }

        const appList = [];
        for (const a of DesktopEntries.applications.values) {
            if (a.noDisplay) continue;
            appList.push({
                kind: "app",
                title: a.name,
                sub: a.genericName || a.comment || "Application",
                extra: ((a.genericName || "") + " " + (a.comment || "") + " " + (a.keywords || []).join(" ")).toLowerCase(),
                icon: a.icon,
                glyph: "󰀻",
                stackCount: 1,
                uses: win.usage[a.id] || 0,
                ref: a
            });
        }
        // most-launched first, then alphabetical
        appList.sort((x, y) => ((win.usage[y.ref.id] || 0) - (win.usage[x.ref.id] || 0)) || x.title.localeCompare(y.title));

        if (q === "") return appList.slice(0, 80);
        return appList
            .map(i => ({ i: i, s: score(i, q) }))
            .filter(x => x.s >= 0)
            .sort((a, b) => a.s - b.s)
            .map(x => x.i)
            .slice(0, 80);
    }

    // The 360° Radial Wheel always shows your Open Windows (or top apps if 0 windows are open),
    // completely decoupled from scrolling the right-hand app list!
    readonly property var wheelItems: (openWindows.length > 0 ? openWindows : listItems).slice(0, maxWheelSlots)
    readonly property int wheelCount: Math.max(1, wheelItems.length)
    readonly property var currentWheelItem: (wheelSel >= 0 && wheelSel < wheelItems.length) ? wheelItems[wheelSel] : null
    readonly property var currentListItem: (listSel >= 0 && listSel < listItems.length) ? listItems[listSel] : null
    readonly property var activeItem: activeFocusStage === "wheel" && currentWheelItem ? currentWheelItem : (currentListItem ?? currentWheelItem)

    // The ring turns so the selected window always comes round to 12 o'clock. `turnDeg` is unwrapped (shortest way
    // round, so stepping from the last window to the first keeps going forward) and sprung.
    property real turnDeg: 0
    Behavior on turnDeg { SpringAnimation { spring: 3.6; damping: 0.42; epsilon: 0.05 } }
    function updatePointerAngle() {
        if (wheelCount <= 0) return;
        const targetMod = (wheelSel / wheelCount) * 360;
        const curMod = ((turnDeg % 360) + 360) % 360;
        let diff = targetMod - curMod;
        if (diff > 180) diff -= 360;
        else if (diff < -180) diff += 360;
        turnDeg = turnDeg + diff;
    }
    onWheelSelChanged: updatePointerAngle()
    onWheelCountChanged: {
        if (wheelSel >= wheelItems.length) wheelSel = Math.max(0, wheelItems.length - 1);
        updatePointerAngle();
    }
    onListSelChanged: {
        if (listSel >= 0 && listSel < listView.count) {
            listView.positionViewAtIndex(listSel, ListView.Contain);
        }
    }
    onListItemsChanged: {
        if (listSel >= listItems.length) listSel = Math.max(0, listItems.length - 1);
    }

    function stepWheel(delta) {
        const n = wheelItems.length;
        if (n === 0) return;
        activeFocusStage = "wheel";
        wheelSel = ((wheelSel + delta) % n + n) % n;
    }

    function stepList(delta) {
        const n = listItems.length;
        if (n === 0) return;
        activeFocusStage = "list";
        listSel = ((listSel + delta) % n + n) % n;
    }

    Process { id: clipProc }
    // How often each app was launched from here, so the list opens with the ones you actually use.
    property var usage: ({})
    FileView {
        id: usageFile
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/slantshell/launches.json"
        printErrors: false
        onLoaded: { try { win.usage = JSON.parse(usageFile.text()) || {}; } catch (e) { win.usage = {}; } }
    }
    Process { id: usageDir; command: ["mkdir", "-p", usageFile.path.replace(/\/[^\/]*$/, "")] }
    function countLaunch(id) {
        const u = Object.assign({}, usage);
        u[id] = (u[id] || 0) + 1;
        usage = u;
        usageDir.running = true;
        usageFile.setText(JSON.stringify(u));
    }
    // Focus a window through Hyprland (by its address), after the switcher has closed and let go of the keyboard;
    // `Toplevel.activate()` is ignored while our layer still holds exclusive focus, and does not change workspace.
    property string pendingAddr: ""
    function focusWindow(t) {
        let addr = "";
        for (const h of Hyprland.toplevels.values) if (h.wayland === t) { addr = h.address; break; }
        if (addr === "") { t.activate(); return; }
        pendingAddr = addr.startsWith("0x") ? addr : "0x" + addr;
        focusLater.restart();
    }
    Timer {
        id: focusLater
        interval: 90
        onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + win.pendingAddr + "\" })"])
    }
    function activate(item) {
        if (win.calcResult !== "" && item === null) {
            clipProc.command = ["wl-copy", win.calcResult];
            clipProc.running = true;
            closeRequested();
            return;
        }
        if (!item) return;
        if (item.kind === "window") focusWindow(item.ref);
        else if (item.kind === "app") {
            countLaunch(item.ref.id);
            // terminal apps (Neovim, btop, ...) need a terminal around them; execute() alone would run them headless
            if (item.ref.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(item.ref.command));
            else item.ref.execute();
        }
        else if (item.kind === "action") Quickshell.execDetached(item.cmd);
        closeRequested();
    }

    onWantedChanged: {
        if (wanted) {
            mode = "all";
            input.text = "";
            forceSearch = false;
            sweep = 0;
            sweepIn.start();
            sceneAnim = false;
            sceneAnimOn.restart();
            wheelSel = 0;
            listSel = 0;
            turnDeg = 0;
            activeFocusStage = openWindows.length > 0 ? "wheel" : "list";
            Qt.callLater(() => input.forceActiveFocus());
        }
    }

    // =========================================================================
    // BACKDROP (Click outside closes; NO outer rectangular box!)
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        color: "#05060c"
        opacity: 0.64 * win.dim
    }
    MouseArea {
        anchors.fill: parent
        onClicked: win.closeRequested()
    }

    // =========================================================================
    // FLOATING CENTER STAGE (Search Pill + Free-Floating 360° Wheel + Pill Stream)
    // =========================================================================
    Item {
        id: centerStage
        width: 1040
        height: 700
        anchors.centerIn: parent
        opacity: win.openProg

        // ---- TOP FLOATING PILL SEARCH BAR & MODE PILLS ----
        RowLayout {
            id: topDeck
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 52
            spacing: 12
            z: 2
            // unrolls from the lens on the left once the wheel has flown in, rolls back up before it flies out
            readonly property real unroll: win.sm(0.35, 1.0, win.searchP)
            opacity: Math.min(1, unroll * 3)
            transform: Scale { origin.x: 26; origin.y: 26; xScale: Math.max(0.001, topDeck.unroll) }

            // Floating Search Pill (no recursive MultiEffect!)
            Rectangle {
                id: searchPill
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 26
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.52)
                border.width: 1.5

                RowLayout {
                    anchors { fill: parent; leftMargin: 22; rightMargin: 18 }
                    spacing: 10

                    Rectangle {
                        visible: win.mode !== "all"
                        Layout.preferredWidth: modeLbl.implicitWidth + 20
                        Layout.preferredHeight: 28
                        radius: 14
                        color: Theme.accent
                        Text {
                            id: modeLbl
                            anchors.centerIn: parent
                            text: win.mode === "win" ? "@ Windows" : "> Actions"
                            color: Theme.accentText
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Text {
                        text: win.calcResult !== "" ? "󰃬" : "󰍉"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 19
                    }

                    TextInput {
                        id: input
                        Layout.fillWidth: true
                        color: Theme.fg
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 2
                        clip: true
                        focus: true

                        onTextChanged: {
                            if (win.mode === "all" && text === "@") {
                                win.mode = "win";
                                text = "";
                                return;
                            }
                            if (win.mode === "all" && text === ">") {
                                win.mode = "act";
                                text = "";
                                return;
                            }
                            win.listSel = 0;
                            if (text.trim() !== "") win.activeFocusStage = "list";
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const down = event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_J || event.key === Qt.Key_N));
                            const up = event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_K || event.key === Qt.Key_P));
                            if (event.key === Qt.Key_Escape) {
                                if (win.searching && win.openWindows.length > 0) win.toSwitcher();
                                else win.closeRequested();
                            } else if (event.key === Qt.Key_Backspace && input.text === "" && win.mode !== "all") {
                                win.mode = "all";
                            } else if (!win.searching) {
                                // the switcher: everything turns the wheel; Down drops into search
                                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_L) win.stepWheel(1);
                                else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_H || up) win.stepWheel(-1);
                                else if (down) win.forceSearch = true;
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.activate(win.currentWheelItem);
                                else return;
                            } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && input.text === "" && win.openWindows.length > 0) {
                                win.toSwitcher();
                            } else if (down) {
                                win.stepList(1);
                            } else if (up) {
                                win.stepList(-1);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (win.calcResult !== "") win.activate(null);
                                else win.activate(win.currentListItem);
                            } else return;
                            event.accepted = true;
                        }

                        Text {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.mode === "win"
                                ? "Filter open windows… (Backspace to exit)"
                                : (win.mode === "act"
                                    ? "Filter system actions… (Backspace to exit)"
                                    : "Search · @ windows · > actions · 2+2")
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    Rectangle {
                        visible: win.calcResult !== ""
                        Layout.preferredWidth: calcTxt.implicitWidth + 24
                        Layout.preferredHeight: 32
                        radius: 16
                        color: Theme.accent
                        Text {
                            id: calcTxt
                            anchors.centerIn: parent
                            text: "= " + win.calcResult + "  (Enter · copy)"
                            color: Theme.accentText
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: win.activate(null)
                        }
                    }
                }
            }

            // Floating Mode Switcher Pills
            Row {
                spacing: 8
                Repeater {
                    model: [
                        { id: "all", label: "Apps",    icon: "󰀻" },
                        { id: "win", label: "Windows", icon: "󰖯" },
                        { id: "act", label: "Actions", icon: "󰐥" }
                    ]
                    Rectangle {
                        id: mBtn
                        required property var modelData
                        readonly property bool activeMode: win.mode === modelData.id
                        width: 102; height: 52
                        radius: 26
                        color: activeMode
                            ? Theme.accent
                            : (mArea.containsMouse ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.95) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88))
                        border.color: activeMode ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1.2
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: mBtn.modelData.icon
                                color: mBtn.activeMode ? Theme.accentText : Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 15
                            }
                            Text {
                                text: mBtn.modelData.label
                                color: mBtn.activeMode ? Theme.accentText : Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                        MouseArea {
                            id: mArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (mBtn.modelData.id === "win" && win.openWindows.length > 0) win.toSwitcher();
                                else { win.mode = mBtn.modelData.id; win.forceSearch = true; win.listSel = 0; }
                                input.forceActiveFocus();
                            }
                        }
                    }
                }
            }
        }

        // ---- MAIN STAGE: RediWM Free-Floating 360° Window Wheel + Independent App Stream ----
        Item {
            id: mainStage
            anchors.fill: parent

            // =================================================================
            // LEFT STAGE: RediWM 360° Circular Window Switcher (`640 x 640`)
            // =================================================================
            // =================================================================
            // WINDOW SWITCHER: an orbit of windows round a live preview (same family as the Wi-Fi/BT screen).
            // Each open window is a pill (app icon, app name, workspace) on an elliptical ring, joined to the core by
            // a thin beam; the ring turns so the selection comes round to the top, where its pill lifts and lights
            // and its beam carries a travelling pulse. The core is a large live picture of the selected window.
            // Opening: the core pops, then the pills fly out of it one after another.
            // =================================================================
            Item {
                id: wheelStage
                width: 960
                height: 640
                // search: the whole orbit spins, shrinks and flies into the search bar's lens
                readonly property real fly: win.sm(0.0, 0.75, win.searchP)
                readonly property real homeX: (mainStage.width - width) / 2
                readonly property real homeY: (mainStage.height - height) / 2 - 12
                readonly property real lensX: 26 - width / 2
                readonly property real lensY: 26 - height / 2
                x: homeX + (lensX - homeX) * fly
                y: homeY + (lensY - homeY) * fly - Math.sin(Math.PI * fly) * 90
                scale: (1.0 - 0.95 * fly)
                rotation: -300 * fly
                opacity: 1 - win.sm(0.55, 0.85, win.searchP)
                visible: opacity > 0.01
                enabled: !win.searching

                readonly property real cx: width / 2
                readonly property real cy: height / 2 - 10
                readonly property real coreW: 400            // the preview core (16:10-ish, rounded)
                readonly property real coreH: 250
                readonly property real rx: 400               // orbit
                readonly property real ry: 262
                readonly property int n: win.wheelItems.length

                // where satellite i sits (selected one at 12 o'clock), scaled by how far it has flown out
                function satPos(i, g) {
                    const a = (i * 360 / Math.max(1, n) - win.turnDeg - 90) * Math.PI / 180;
                    return { x: cx + Math.cos(a) * rx * g, y: cy + Math.sin(a) * ry * g, a: a };
                }

                // scroll turns the ring: one step per notch (touchpad deltas are added up to a notch's worth)
                property real wheelAcc: 0
                WheelHandler {
                    onWheel: event => {
                        const d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x;
                        wheelStage.wheelAcc += d;
                        while (Math.abs(wheelStage.wheelAcc) >= 120) {
                            const dir = wheelStage.wheelAcc > 0 ? -1 : 1;
                            win.stepWheel(dir);
                            wheelStage.wheelAcc += dir * 120;
                        }
                    }
                }

                // faint orbit rings
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        readonly property real k: index === 0 ? 1 : 1.12
                        x: wheelStage.cx - wheelStage.rx * k * win.sweep; y: wheelStage.cy - wheelStage.ry * k * win.sweep
                        width: 2 * wheelStage.rx * k * win.sweep; height: 2 * wheelStage.ry * k * win.sweep
                        radius: height / 2
                        color: "transparent"
                        border.color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, index === 0 ? 0.08 : 0.04)
                        border.width: 1
                        antialiasing: true
                        visible: win.sweep > 0.02
                    }
                }

                // beams: core edge -> each satellite (the selected one brighter)
                Repeater {
                    model: win.wheelItems
                    Shape {
                        id: beam
                        required property int index
                        readonly property real g: win.sectorGrow(index, wheelStage.n)
                        readonly property var p: wheelStage.satPos(index, g)
                        readonly property bool sel: index === win.wheelSel
                        anchors.fill: parent
                        visible: g > 0.02
                        ShapePath {
                            strokeColor: beam.sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
                                                  : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.13)
                            strokeWidth: beam.sel ? 1.8 : 1
                            fillColor: "transparent"
                            startX: wheelStage.cx + Math.cos(beam.p.a) * wheelStage.coreW * 0.42 * beam.g
                            startY: wheelStage.cy + Math.sin(beam.p.a) * wheelStage.coreH * 0.42 * beam.g
                            PathLine { x: beam.p.x; y: beam.p.y }
                        }
                    }
                }
                // a pulse running along the selected beam, out from the core
                Rectangle {
                    id: pulse
                    readonly property var p: wheelStage.satPos(win.wheelSel, win.sectorGrow(win.wheelSel, wheelStage.n))
                    readonly property real sx: wheelStage.cx + Math.cos(p.a) * wheelStage.coreW * 0.42
                    readonly property real sy: wheelStage.cy + Math.sin(p.a) * wheelStage.coreH * 0.42
                    property real t: 0
                    NumberAnimation on t { from: 0; to: 1; duration: 1100; loops: Animation.Infinite; running: win.wanted && !win.searching }
                    width: 8; height: 8; radius: 4
                    x: sx + (p.x - sx) * t - 4
                    y: sy + (p.y - sy) * t - 4
                    color: Theme.accent
                    opacity: Math.sin(Math.PI * t) * win.sweep
                    visible: wheelStage.n > 0
                    Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; z: -1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) }
                }

                // ---- the core: a large live picture of the selected window ----
                Item {
                    id: hub
                    readonly property var item: win.currentWheelItem
                    readonly property bool isWin: item !== null && item.kind === "window"
                    width: wheelStage.coreW
                    height: wheelStage.coreH
                    x: wheelStage.cx - width / 2
                    y: wheelStage.cy - height / 2
                    z: 5
                    property real pop: win.wanted ? 1 : 0
                    Behavior on pop { SpringAnimation { spring: 4.2; damping: 0.42; epsilon: 0.002 } }
                    scale: Math.max(0, pop) * swapK
                    // a little zoom-blink when the selection changes
                    property real swapK: 1
                    SequentialAnimation {
                        id: swapBlink
                        NumberAnimation { target: hub; property: "swapK"; to: 0.94; duration: 90; easing.type: Easing.OutCubic }
                        NumberAnimation { target: hub; property: "swapK"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Connections { target: win; function onWheelSelChanged() { if (win.wanted) swapBlink.restart(); } }

                    // halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 36; height: parent.height + 36; radius: 34
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
                    }
                    Rectangle {
                        id: coreFrame
                        anchors.fill: parent
                        radius: 22
                        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.92)
                        border.color: Theme.accent
                        border.width: 2
                        antialiasing: true
                    }
                    Item {
                        anchors { fill: parent; margins: 6 }
                        visible: hub.isWin && preview.hasContent
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: hubMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }
                        ScreencopyView {
                            id: preview
                            anchors.centerIn: parent
                            // fit the whole window in the frame
                            readonly property real ar: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                            readonly property real boxAr: parent.width / parent.height
                            width: ar >= boxAr ? parent.width : parent.height * ar
                            height: ar >= boxAr ? parent.width / ar : parent.height
                            captureSource: hub.isWin && win.wanted ? hub.item.ref : null
                            live: win.wanted
                            onCaptureSourceChanged: swapIn.restart()
                            NumberAnimation { id: swapIn; target: preview; property: "opacity"; from: 0.2; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        id: hubMask
                        anchors { fill: parent; margins: 6 }
                        radius: 17
                        visible: false
                        layer.enabled: true
                    }
                    // app icon badge on the frame's bottom edge
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height - 22
                        width: 44; height: 44; radius: 22
                        color: Theme.bg
                        border.color: Theme.accent
                        border.width: 2
                        visible: hub.item !== null
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 28
                            visible: hub.item !== null && hub.item.kind !== "action"
                            source: hub.item && hub.item.kind !== "action" ? Quickshell.iconPath(hub.item.icon, "application-x-executable") : ""
                        }
                    }
                    // no live picture (a window on a hidden workspace, or an app): a big icon instead
                    IconImage {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -10
                        implicitSize: 96
                        visible: hub.item !== null && hub.item.kind !== "action" && !(hub.isWin && preview.hasContent)
                        source: hub.item && hub.item.kind !== "action" ? Quickshell.iconPath(hub.item.icon, "application-x-executable") : ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !hub.isWin
                        text: hub.item ? "" : "No windows"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 14
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (win.currentWheelItem) win.activate(win.currentWheelItem)
                    }
                }

                // ---- the satellites ----
                Repeater {
                    model: win.wheelItems
                    Item {
                        id: sat
                        required property var modelData
                        required property int index
                        readonly property bool isSel: index === win.wheelSel
                        readonly property real g: win.sectorGrow(index, wheelStage.n)
                        readonly property var p: wheelStage.satPos(index, g)
                        width: 188; height: 54
                        x: p.x - width / 2
                        y: p.y - height / 2
                        z: isSel ? 8 : 6
                        opacity: Math.min(1, g * 1.5)
                        property real lift: isSel ? 1 : 0
                        Behavior on lift { SpringAnimation { spring: 5; damping: 0.5; epsilon: 0.005 } }
                        scale: Math.max(0.01, g) * (1 + 0.14 * lift + (satMouse.containsMouse && !isSel ? 0.05 : 0))

                        Rectangle {
                            anchors.fill: parent
                            radius: 27
                            color: sat.isSel ? Theme.accent : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.9)
                            border.color: sat.isSel ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                            border.width: 1
                            antialiasing: true
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Rectangle {
                                width: 34; height: 34; radius: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: sat.isSel ? Qt.rgba(0, 0, 0, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 22
                                    source: sat.modelData.kind !== "action" ? Quickshell.iconPath(sat.modelData.icon, "application-x-executable") : ""
                                }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0
                                Text {
                                    width: 120
                                    text: sat.modelData.kind === "window" ? sat.modelData.app : sat.modelData.title
                                    color: sat.isSel ? Theme.accentText : Theme.fg
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                                Text {
                                    width: 120
                                    text: sat.modelData.ws ? "workspace " + sat.modelData.ws : (sat.modelData.kind === "window" ? "window" : "app")
                                    color: sat.isSel ? Qt.rgba(Theme.accentText.r, Theme.accentText.g, Theme.accentText.b, 0.75) : Theme.fgDim
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                }
                            }
                        }
                        MouseArea {
                            id: satMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // no hover-select (the ring would turn under the pointer forever): click picks it,
                            // a click on the picked one focuses it
                            onClicked: {
                                win.activeFocusStage = "wheel";
                                if (sat.isSel) win.activate(sat.modelData);
                                else win.wheelSel = sat.index;
                            }
                        }
                    }
                }

                // caption: the selected window's full title, under the core
                Text {
                    id: capTitle
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: wheelStage.cy + wheelStage.coreH / 2 + 34
                    z: 7
                    width: Math.min(implicitWidth, 520)
                    horizontalAlignment: Text.AlignHCenter
                    opacity: win.sweep
                    text: win.currentWheelItem ? win.currentWheelItem.title : ""
                    color: Theme.fg
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.bold: true
                    onTextChanged: capIn.restart()
                    ParallelAnimation {
                        id: capIn
                        NumberAnimation { target: capShift; property: "y"; from: 8; to: 0; duration: 220; easing.type: Easing.OutCubic }
                    }
                    transform: Translate { id: capShift }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: mainStage.height - 6
                opacity: (1 - win.sm(0.0, 0.3, win.searchP)) * 0.8
                visible: opacity > 0.01
                text: "type to search  ·  ↓ apps  ·  ←/→ or scroll to pick  ·  Enter to focus"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 11
            }

            // =================================================================
            // RIGHT STAGE: Independent App & Command Pill Stream (NO outer box!)
            // =================================================================
            ListView {
                id: listView
                width: 680
                x: (mainStage.width - width) / 2
                y: 70
                height: mainStage.height - 70
                // the list waits for the bar to unroll, then drops in
                readonly property real drop: win.sm(0.45, 1.0, win.searchP)
                opacity: drop
                visible: drop > 0.01
                enabled: win.searching
                transform: Translate { y: (1 - listView.drop) * -24 }
                clip: true
                spacing: 8
                model: win.listItems
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: win.listSel
                highlightFollowsCurrentItem: false
                // one slanted highlight that glides between rows on a spring (instead of each row lighting up)
                highlight: Item {
                    width: listView.width
                    height: 58
                    z: 0
                    y: listView.currentItem ? listView.currentItem.y : 0
                    Behavior on y { SpringAnimation { spring: 6.0; damping: 0.62; epsilon: 0.2 } }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, win.activeFocusStage === "list" ? 0.85 : 0.45)
                            strokeColor: Theme.accent
                            strokeWidth: win.activeFocusStage === "list" ? 1.6 : 0.8
                            startX: 14; startY: 0
                            PathLine { x: listView.width - 4; y: 0 }
                            PathLine { x: listView.width - 14; y: 58 }
                            PathLine { x: 4; y: 58 }
                            PathLine { x: 14; y: 0 }
                        }
                    }
                    EdgeSpark {      // the highlight's border is lightning
                        anchors.fill: parent
                        visible: Theme.lightning && win.searching
                        points: [[14, 1], [listView.width - 5, 1], [listView.width - 15, 57], [5, 57]]
                        closed: true
                        intensity: 0.28
                        step: 5
                        running: win.wanted
                    }
                    Rectangle {      // accent tab on the left edge
                        x: 4; y: 0; width: 4; height: 58
                        color: Theme.accent
                        antialiasing: true
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -10 / 58, 0, 10, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                    }
                }
                // rows fly in one after another when the switcher opens
                property bool entered: win.wanted

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index
                    readonly property bool isSel: win.listSel === index
                    readonly property bool isStageFocused: win.activeFocusStage === "list" && isSel
                    readonly property bool isWin: modelData.kind === "window"
                    width: listView.width
                    height: 58
                    z: 1

                    property real fly: 0
                    readonly property real cascade: win.sm(0.45 + Math.min(8, index) * 0.05, 0.75 + Math.min(8, index) * 0.05, win.searchP)
                    opacity: fly * cascade
                    transform: Translate { x: (1 - rowItem.fly) * 40; y: (1 - rowItem.cascade) * -18 }
                    Component.onCompleted: flyIn.start()
                    SequentialAnimation {
                        id: flyIn
                        PauseAnimation { duration: Math.min(8, rowItem.index) * 35 }
                        NumberAnimation { target: rowItem; property: "fly"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    }
                    Connections { target: win; function onWantedChanged() { if (win.wanted) { rowItem.fly = 0; flyIn.restart(); } } }

                    Item {
                        id: rowCard
                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                        // a faint slanted plate under the rows the highlight is not on
                        Shape {
                            anchors.fill: parent
                            visible: !rowItem.isSel
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: rowMouse.containsMouse ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.7) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)
                                strokeColor: "transparent"
                                startX: 10; startY: 0
                                PathLine { x: rowCard.width; y: 0 }
                                PathLine { x: rowCard.width - 10; y: rowCard.height }
                                PathLine { x: 0; y: rowCard.height }
                                PathLine { x: 10; y: 0 }
                            }
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36

                                IconImage {
                                    anchors.fill: parent
                                    visible: rowItem.modelData.kind !== "action"
                                    implicitSize: 36
                                    source: rowItem.modelData.kind !== "action"
                                        ? Quickshell.iconPath(rowItem.modelData.icon, "application-x-executable")
                                        : ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: rowItem.modelData.kind === "action"
                                    text: rowItem.modelData.glyph || "󰐥"
                                    color: Theme.accent
                                    font.family: Theme.font
                                    font.pixelSize: 22
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.title
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.bold: rowItem.isSel
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.sub || ""
                                    color: rowItem.isSel ? Theme.accent : Theme.fgDim
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }
                            }

                            Text {      // only the selected row says what Enter does
                                opacity: rowItem.isSel ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                text: (rowItem.isWin ? "focus" : (rowItem.modelData.kind === "action" ? "run" : "open")) + "  ↵"
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            win.activeFocusStage = "list";
                            win.listSel = rowItem.index;
                        }
                        onClicked: win.activate(rowItem.modelData)
                    }
                }
            }
        }
    }
}
