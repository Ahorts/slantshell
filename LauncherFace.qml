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
//   - Left stage (Window Switcher Wheel): RediWM-style 360° analytic circular sector wheel (`464x464`) dedicated
//     to your open Hyprland windows (or top apps when no windows are open). Has its OWN independent selection
//     (`wheelSel`) and unwrapped shortest-path pointer angle (`pointerDeg`), so wrapping from the last sector
//     to the first steps smoothly forward across 12 o'clock instead of spinning backwards!
//   - Right stage (App & Command Stream): independent scrollable list (`listSel`) so scrolling through installed
//     apps never turns the radial window wheel on the left.
//   - Top stage: floating pill search bar with prefix modes (`@` windows, `>` actions, inline math calculator).
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    property real openProg: wanted ? 1 : 0
    Behavior on openProg { SpringAnimation { spring: 3.8; damping: 0.44; epsilon: 0.002 } }

    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    visible: wanted || dim > 0.004 || openProg > 0.004

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
    Behavior on searchP { SpringAnimation { spring: 3.6; damping: 0.5; epsilon: 0.002 } }
    function sm(a, b, x) { const t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t); }
    onSearchingChanged: {
        activeFocusStage = searching ? "list" : "wheel";
        if (wanted) wheelSpark.burst(1);
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
        { kind: "action", title: "Lock Session",        sub: "Lock screen via loginctl",             icon: "", glyph: "󰌾", cmd: ["loginctl", "lock-session"] },
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

    // Right-hand scrollable stream items (Applications, Windows, or Actions)
    readonly property var listItems: {
        if (!wanted) return [];
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

    // Unwrapped shortest-path pointer angle (degrees, 0 = 12 o'clock, clockwise):
    // Going from the last sector (e.g. 315°) to sector 0 (0°) adds +45° (to 360°) instead of animating backwards to 0°!
    property real pointerDeg: 0
    Behavior on pointerDeg { SpringAnimation { spring: 5.0; damping: 0.54; epsilon: 0.08 } }

    function updatePointerAngle() {
        if (wheelCount <= 0) return;
        const targetMod = (wheelSel / wheelCount) * 360;
        const curMod = ((pointerDeg % 360) + 360) % 360;
        let diff = targetMod - curMod;
        if (diff > 180) diff -= 360;
        else if (diff < -180) diff += 360;
        pointerDeg = pointerDeg + diff;
    }

    property real selExtrude: 1
    onWheelSelChanged: {
        updatePointerAngle();
        if (wanted) wheelSpark.burst(0.55);
        selExtrude = 0.28;
        extrudeRecover.restart();
        wheelCanvas.requestPaint();
    }
    onWheelCountChanged: {
        if (wheelSel >= wheelItems.length) wheelSel = Math.max(0, wheelItems.length - 1);
        updatePointerAngle();
        wheelCanvas.requestPaint();
    }
    onListSelChanged: {
        if (listSel >= 0 && listSel < listView.count) {
            listView.positionViewAtIndex(listSel, ListView.Contain);
        }
    }
    onListItemsChanged: {
        if (listSel >= listItems.length) listSel = Math.max(0, listItems.length - 1);
    }

    Timer { id: extrudeRecover; interval: 16; onTriggered: win.selExtrude = 1 }
    Behavior on selExtrude { SpringAnimation { spring: 5.2; damping: 0.46; epsilon: 0.005 } }
    onSelExtrudeChanged: wheelCanvas.requestPaint()
    onOpenProgChanged: wheelCanvas.requestPaint()
    onPointerDegChanged: wheelCanvas.requestPaint()

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
        else if (item.kind === "app") { countLaunch(item.ref.id); item.ref.execute(); }
        else if (item.kind === "action") Quickshell.execDetached(item.cmd);
        closeRequested();
    }

    onWantedChanged: {
        if (wanted) {
            mode = "all";
            input.text = "";
            forceSearch = false;
            wheelSel = 0;
            listSel = 0;
            pointerDeg = 0;
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
        width: 960
        height: 556
        anchors.centerIn: parent
        scale: 0.88 + 0.12 * win.openProg
        opacity: Math.min(1, win.openProg * 1.4)

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
            // LEFT STAGE: RediWM 360° Circular Window Switcher (`464 x 464`)
            // =================================================================
            Item {
                id: wheelStage
                width: 464
                height: 464
                // switcher: centre stage, a little larger. search: spins, shrinks and flies into the lens
                readonly property real fly: win.sm(0.0, 0.75, win.searchP)
                readonly property real homeX: (mainStage.width - width) / 2
                readonly property real homeY: (mainStage.height - height) / 2 + 10
                readonly property real lensX: 26 - width / 2
                readonly property real lensY: 26 - height / 2
                x: homeX + (lensX - homeX) * fly
                y: homeY + (lensY - homeY) * fly - Math.sin(Math.PI * fly) * 90     // arcs up on the way
                scale: (1.12 - 1.07 * fly)
                rotation: -300 * fly
                opacity: 1 - win.sm(0.55, 0.85, win.searchP)
                visible: opacity > 0.01
                enabled: !win.searching

                readonly property real cx: width / 2
                readonly property real cy: height / 2
                readonly property real hubR: 74
                readonly property real innerR: 90
                readonly property real baseOuterR: 188
                readonly property real selExtraR: 24

                WheelHandler {
                    onWheel: event => win.stepWheel(event.angleDelta.y > 0 ? -1 : 1)
                }

                Canvas {
                    id: wheelCanvas
                    anchors.fill: parent
                    antialiasing: true

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const cx = wheelStage.cx, cy = wheelStage.cy;
                        const n = win.wheelItems.length;
                        const grow = Math.max(0.01, Math.min(1.15, win.openProg));

                        // Soft radial shadow/halo under the wheel
                        const amb = ctx.createRadialGradient(cx, cy, wheelStage.hubR * 0.5, cx, cy, 226);
                        amb.addColorStop(0.0, Qt.rgba(0, 0, 0, 0.55));
                        amb.addColorStop(0.75, Qt.rgba(0, 0, 0, 0.28));
                        amb.addColorStop(1.0, "transparent");
                        ctx.fillStyle = amb;
                        ctx.beginPath();
                        ctx.arc(cx, cy, 226, 0, Math.PI * 2);
                        ctx.fill();

                        // Outer dark disc backing
                        ctx.beginPath();
                        ctx.arc(cx, cy, wheelStage.baseOuterR * grow + 8, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.86);
                        ctx.fill();

                        if (n > 0) {
                            const slotSpan = (Math.PI * 2) / n;
                            const gap = n > 1 ? Math.min(0.05, slotSpan * 0.10) : 0;

                            for (let i = 0; i < n; i++) {
                                const it = win.wheelItems[i];
                                const isSel = (i === win.wheelSel);
                                const midA = -Math.PI / 2 + i * slotSpan;
                                const a0 = midA - (slotSpan - gap) / 2;
                                const a1 = midA + (slotSpan - gap) / 2;

                                const ext = isSel ? wheelStage.selExtraR * win.selExtrude : 0;
                                const r0 = wheelStage.innerR;
                                const r1 = r0 + (wheelStage.baseOuterR + ext - r0) * grow;

                                // Stacked sub-arcs behind if window group has multiple instances
                                const stacks = Math.min(3, it.stackCount || 1);
                                for (let d = stacks - 1; d >= 1; d--) {
                                    const sr0 = r1 + d * 6;
                                    const sr1 = r1 + d * 6 + 4;
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, sr1, a0 + 0.02, a1 - 0.02, false);
                                    ctx.arc(cx, cy, sr0, a1 - 0.02, a0 + 0.02, true);
                                    ctx.closePath();
                                    ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, isSel ? 0.35 : 0.15);
                                    ctx.fill();
                                }

                                const sGrad = ctx.createRadialGradient(cx, cy, r0, cx, cy, r1);
                                if (isSel) {
                                    sGrad.addColorStop(0.0, Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.96));
                                    sGrad.addColorStop(0.72, Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.78));
                                    sGrad.addColorStop(1.0, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.48));
                                } else {
                                    sGrad.addColorStop(0.0, Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.88));
                                    sGrad.addColorStop(1.0, Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.78));
                                }

                                ctx.beginPath();
                                ctx.arc(cx, cy, r1, a0, a1, false);
                                ctx.arc(cx, cy, r0, a1, a0, true);
                                ctx.closePath();
                                ctx.fillStyle = sGrad;
                                ctx.fill();

                                ctx.lineWidth = isSel ? 1.8 : 1.0;
                                ctx.strokeStyle = isSel ? Theme.accent : Qt.rgba(1, 1, 1, 0.11);
                                ctx.stroke();

                                if (isSel) {
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r1 + 2, a0 + 0.01, a1 - 0.01, false);
                                    ctx.strokeStyle = Theme.accent;
                                    ctx.lineWidth = 5.0;
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                } else if (it.kind === "window") {
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, r1, a0 + 0.04, a1 - 0.04, false);
                                    ctx.strokeStyle = Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, 0.65);
                                    ctx.lineWidth = 2.4;
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                }
                            }
                        }

                        // Central Hub Circle + Unwrapped Shortest-Path Directional Pointer
                        ctx.save();
                        ctx.translate(cx, cy);

                        ctx.beginPath();
                        ctx.arc(0, 0, wheelStage.hubR, 0, Math.PI * 2);
                        ctx.fillStyle = Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.96);
                        ctx.fill();
                        ctx.lineWidth = 1.8;
                        ctx.strokeStyle = win.activeFocusStage === "wheel" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Qt.rgba(1, 1, 1, 0.14);
                        ctx.stroke();

                        if (n > 0) {
                            const pRad = (win.pointerDeg - 90) * Math.PI / 180;
                            ctx.save();
                            ctx.rotate(pRad);

                            ctx.beginPath();
                            ctx.arc(0, 0, wheelStage.hubR, -0.34, 0.34);
                            ctx.strokeStyle = Theme.accent;
                            ctx.lineWidth = 3.5;
                            ctx.lineCap = "round";
                            ctx.stroke();

                            ctx.beginPath();
                            ctx.moveTo(wheelStage.hubR + 10, 0);
                            ctx.lineTo(wheelStage.hubR - 2, -6.5);
                            ctx.lineTo(wheelStage.hubR - 2, 6.5);
                            ctx.closePath();
                            ctx.fillStyle = Theme.accent;
                            ctx.fill();
                            ctx.restore();
                        }

                        ctx.restore();
                    }
                }

                // Sector Icons & Labels
                Repeater {
                    model: win.wheelItems

                    Item {
                        id: secItem
                        required property var modelData
                        required property int index
                        readonly property bool isSel: index === win.wheelSel
                        readonly property real slotSpan: (Math.PI * 2) / win.wheelCount
                        readonly property real midA: -Math.PI / 2 + index * slotSpan
                        readonly property real midR: (wheelStage.innerR + wheelStage.baseOuterR + (isSel ? wheelStage.selExtraR * 0.55 : 0)) * 0.5 * Math.min(1, win.openProg)

                        width: 82; height: 58
                        x: wheelStage.cx + Math.cos(midA) * midR - width / 2
                        y: wheelStage.cy + Math.sin(midA) * midR - height / 2
                        scale: isSel ? 1.14 : 0.96
                        Behavior on scale { SpringAnimation { spring: 5.0; damping: 0.48 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Item {
                                width: 34; height: 34
                                anchors.horizontalCenter: parent.horizontalCenter

                                IconImage {
                                    anchors.fill: parent
                                    visible: secItem.modelData.kind !== "action"
                                    implicitSize: 34
                                    source: secItem.modelData.kind !== "action"
                                        ? Quickshell.iconPath(secItem.modelData.icon, "application-x-executable")
                                        : ""
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: secItem.modelData.kind === "action"
                                    text: secItem.modelData.glyph || "󰀻"
                                    color: secItem.isSel ? Theme.accent : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: 24
                                }
                            }

                            Text {
                                width: 78
                                horizontalAlignment: Text.AlignHCenter
                                text: (secItem.modelData.kind === "window" ? secItem.modelData.app : secItem.modelData.title)
                                      + (secItem.modelData.ws ? "  ·  " + secItem.modelData.ws : "")
                                color: secItem.isSel ? Theme.fg : Theme.fgDim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 10
                                font.bold: secItem.isSel
                            }
                        }
                    }
                }

                // a faint current round the rim; it flares as the selection moves and when the scene changes
                EdgeSpark {
                    id: wheelSpark
                    anchors.fill: parent
                    ring: true
                    cx: wheelStage.cx; cy: wheelStage.cy
                    r: wheelStage.baseOuterR + 9
                    intensity: 0.18
                    running: win.wanted
                }

                // Central hub: a live picture of the selected window (circle-cropped), its app icon pinned at the
                // bottom edge. Apps (no window yet) show their icon instead.
                Item {
                    id: hub
                    readonly property var item: win.currentWheelItem
                    readonly property bool isWin: item !== null && item.kind === "window"
                    width: wheelStage.hubR * 2 - 6
                    height: width
                    x: wheelStage.cx - width / 2
                    y: wheelStage.cy - height / 2
                    scale: Math.min(1, win.openProg)

                    // the capture, masked to a circle
                    Item {
                        id: previewBox
                        anchors.fill: parent
                        visible: hub.isWin
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
                            // cover the circle, keeping the window's aspect ratio
                            readonly property real ar: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 9
                            width: ar >= 1 ? parent.height * ar : parent.width
                            height: ar >= 1 ? parent.height : parent.width / ar
                            captureSource: hub.isWin && win.wanted ? hub.item.ref : null
                            live: win.wanted
                            // a soft swap: each new window fades/zooms in
                            onCaptureSourceChanged: swapIn.restart()
                            NumberAnimation { id: swapIn; target: preview; property: "opacity"; from: 0.15; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        }
                        Rectangle {        // darken the bottom so the icon badge reads
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.55; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                            }
                        }
                    }
                    Rectangle {
                        id: hubMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }
                    // ring around the preview
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: win.activeFocusStage === "wheel" ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                        border.width: 2
                        antialiasing: true
                    }
                    IconImage {
                        readonly property real sz: hub.isWin ? 28 : 46
                        width: sz; height: sz
                        implicitSize: sz
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: hub.isWin ? parent.height - sz * 0.75 : (parent.height - sz) / 2
                        visible: hub.item !== null && hub.item.kind !== "action"
                        source: hub.item && hub.item.kind !== "action" ? Quickshell.iconPath(hub.item.icon, "application-x-executable") : ""
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !hub.item || hub.item.kind === "action"
                        text: hub.item ? (hub.item.glyph || "󰀻") : "󰍉"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 30
                    }
                }

                // caption under the wheel: the selected window's full title and where it lives
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: wheelStage.cy + wheelStage.baseOuterR + wheelStage.selExtraR + 2
                    opacity: Math.min(1, win.openProg)
                    spacing: 0
                    Text {
                        id: capTitle
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, 440)
                        horizontalAlignment: Text.AlignHCenter
                        text: win.currentWheelItem ? win.currentWheelItem.title : "No windows"
                        color: Theme.fg
                        elide: Text.ElideMiddle
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.bold: true
                        // rises into place when the selection changes (same motion as the bar's lyrics)
                        onTextChanged: capIn.restart()
                        ParallelAnimation {
                            id: capIn
                            NumberAnimation { target: capTitle; property: "opacity"; from: 0; to: 1; duration: 200 }
                            NumberAnimation { target: capShift; property: "y"; from: 8; to: 0; duration: 220; easing.type: Easing.OutCubic }
                        }
                        transform: Translate { id: capShift }
                    }
                }

                // Polar Mouse Hit-Testing for the 360° Sector Wheel & Hub
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: mouse => {
                        const dx = mouse.x - wheelStage.cx, dy = mouse.y - wheelStage.cy;
                        const r = Math.hypot(dx, dy);
                        if (r < wheelStage.innerR || r > wheelStage.baseOuterR + wheelStage.selExtraR + 14) return;
                        const n = win.wheelItems.length;
                        if (n === 0) return;
                        const slotSpan = (Math.PI * 2) / n;
                        let ang = Math.atan2(dy, dx) + Math.PI / 2 + slotSpan / 2;
                        ang = ((ang % (Math.PI * 2)) + Math.PI * 2) % (Math.PI * 2);
                        const idx = Math.floor(ang / slotSpan) % n;
                        win.activeFocusStage = "wheel";
                        if (win.wheelSel !== idx) win.wheelSel = idx;
                    }
                    onClicked: mouse => {
                        const dx = mouse.x - wheelStage.cx, dy = mouse.y - wheelStage.cy;
                        const r = Math.hypot(dx, dy);
                        if (r <= wheelStage.baseOuterR + wheelStage.selExtraR + 14 && win.currentWheelItem) {
                            win.activate(win.currentWheelItem);
                        }
                    }
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
