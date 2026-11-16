import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// App switcher / launcher. The island morphs into it (same trick as the dashboard):
//   - a strip of your open windows across the top (pick one to switch to it)
//   - a search box, and a grid of installed apps below (pick one to launch it)
// Type to filter. Arrows move, Enter selects, Esc closes. The dark backdrop fades in on its own
// slower timeline, separate from the panel's animation.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    readonly property bool onFocusedScreen: Hyprland.focusedMonitor?.name === screen?.name
    readonly property bool wanted: open && onFocusedScreen

    // ---- Animation state ----
    // Backdrop: its own gentle fade (no spring, no overshoot).
    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    // Panel: width springs out of the island first, height follows a beat later.
    property real pw: wanted ? 1 : 0
    property real ph: wanted ? 1 : 0
    Behavior on pw { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
    Behavior on ph {
        SequentialAnimation {
            PauseAnimation { duration: win.wanted ? 80 : 0 }
            NumberAnimation { duration: win.wanted ? 520 : 340; easing.type: Easing.OutCubic }
        }
    }
    readonly property real contentOpacity: Math.max(0, Math.min(1, (ph - 0.6) / 0.35))

    visible: wanted || dim > 0.002 || pw > 0.002 || ph > 0.002

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-launcher"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // ---- Layout constants ----
    readonly property int cols: 6
    readonly property int cellW: 118
    readonly property int cellH: 100
    readonly property int visibleRows: 3
    readonly property int pad: 30
    readonly property int startW: 230      // the island's resting size and position
    readonly property int startH: 40
    readonly property int topGap: 8
    readonly property real fullW: cols * cellW + pad * 2 + 28
    readonly property real fullH: pad * 0.8 + 44 + 14 + (wins.length > 0 ? 58 + 14 : 0) + visibleRows * cellH + pad * 0.8

    // ---- Data ----
    property int sel: 0

    function score(item, q) {
        const name = item.title.toLowerCase();
        if (name.startsWith(q)) return 0;
        if (name.includes(" " + q)) return 1;
        if (name.includes(q)) return 2;
        if (item.extra.includes(q)) return 3;
        return -1;
    }

    // { wins: [...], apps: [...] }, filtered by the search text.
    readonly property var found: {
        if (!wanted) return { wins: [], apps: [] };
        const q = input.text.trim().toLowerCase();
        const wins = [], apps = [];

        for (const t of ToplevelManager.toplevels.values) {
            const entry = DesktopEntries.heuristicLookup(t.appId);
            wins.push({
                kind: "window",
                title: t.title || t.appId,
                extra: (t.appId + " " + t.title).toLowerCase(),
                icon: entry ? entry.icon : t.appId,
                ref: t
            });
        }
        for (const a of DesktopEntries.applications.values) {
            if (a.noDisplay) continue;
            apps.push({
                kind: "app",
                title: a.name,
                extra: ((a.genericName || "") + " " + (a.comment || "") + " " + (a.keywords || []).join(" ")).toLowerCase(),
                icon: a.icon,
                ref: a
            });
        }
        apps.sort((x, y) => x.title.localeCompare(y.title));

        if (q === "") return { wins: wins.slice(0, 6), apps: apps.slice(0, 120) };
        const filt = list => list
            .map(i => ({ i: i, s: score(i, q) }))
            .filter(x => x.s >= 0)
            .sort((a, b) => a.s - b.s)
            .map(x => x.i);
        return { wins: filt(wins).slice(0, 6), apps: filt(apps).slice(0, 120) };
    }
    readonly property var wins: found.wins
    readonly property var apps: found.apps
    readonly property int total: wins.length + apps.length
    readonly property var current: sel < wins.length ? wins[sel] : (apps[sel - wins.length] ?? null)

    onTotalChanged: if (sel >= total) sel = Math.max(0, total - 1)
    onSelChanged: if (sel >= wins.length && apps.length > 0) grid.positionViewAtIndex(sel - wins.length, GridView.Contain)

    function move(dx, dy) {
        const w = wins.length;
        if (total === 0) return;
        if (dx !== 0) {
            sel = Math.max(0, Math.min(total - 1, sel + dx));
        } else if (dy > 0) {
            if (sel < w && apps.length > 0) sel = w;                          // windows -> first row of apps
            else sel = Math.min(total - 1, sel + cols);
        } else if (dy < 0) {
            if (sel >= w && sel - w < cols && w > 0) sel = Math.min(w - 1, sel - w);   // apps -> windows
            else if (sel >= w + cols) sel -= cols;
        }
    }

    function activate(item) {
        if (!item) return;
        if (item.kind === "window") item.ref.activate();
        else item.ref.execute();
        closeRequested();
    }

    onWantedChanged: {
        if (wanted) {
            input.text = "";
            sel = 0;
            Qt.callLater(() => input.forceActiveFocus());
        }
    }

    // ---- Backdrop: fades on its own timeline ----
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 * win.dim }
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

    // ---- The panel morphing out of the island ----
    SkewPanel {
        id: panel
        glass: true
        skewL: -(14 + 2 * win.ph)
        skewR: 14 + 2 * win.ph        // same trapezoid as the island and the dashboard
        clip: true
        opacity: Math.min(1, win.pw * 8)
        width: win.startW + (win.fullW - win.startW) * win.pw
        height: win.startH + (win.fullH - win.startH) * win.ph
        x: Math.round((win.width - width) / 2)
        y: win.topGap

        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close us

        Item {
            id: content
            width: win.fullW
            height: win.fullH
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: win.contentOpacity
            scale: 0.96 + 0.04 * win.contentOpacity
            transformOrigin: Item.Top

            ColumnLayout {
                anchors { fill: parent; leftMargin: win.pad + 14; rightMargin: win.pad + 14; topMargin: win.pad * 0.8; bottomMargin: win.pad * 0.8 }
                spacing: 14

                // Search
                SkewPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    skewL: -8
                    skewR: 8
                    fill: Theme.surface
                    strokeWidth: 0

                    Text {
                        id: glass
                        anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                        text: "󰍉"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 5
                    }

                    TextInput {
                        id: input
                        anchors { left: glass.right; leftMargin: 12; right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                        color: Theme.fg
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 3
                        clip: true
                        focus: true

                        onTextChanged: win.sel = 0

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (event.key === Qt.Key_Escape) win.closeRequested();
                            else if (event.key === Qt.Key_Right || (ctrl && event.key === Qt.Key_L)) win.move(1, 0);
                            else if (event.key === Qt.Key_Left || (ctrl && event.key === Qt.Key_H)) win.move(-1, 0);
                            else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) win.move(0, 1);
                            else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) win.move(0, -1);
                            else if (event.key === Qt.Key_Tab) win.move(1, 0);
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.activate(win.current);
                            else return;
                            event.accepted = true;
                        }

                        Text {
                            visible: input.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search apps and windows…"
                            color: Theme.fgDim
                            font: input.font
                        }
                    }
                }

                // Open windows
                Row {
                    id: winRow
                    visible: win.wins.length > 0
                    Layout.preferredHeight: 58
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: win.wins

                        SkewPanel {
                            id: chip
                            required property var modelData
                            required property int index
                            readonly property bool selected: win.sel === index
                            width: (winRow.width - 5 * 10) / 6
                            height: 58
                            skew: -8
                            fill: selected ? Theme.surface : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.45)
                            stroke: selected ? Theme.accent : Theme.accentContainer
                            strokeWidth: selected ? 2 : 0

                            Row {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                spacing: 8
                                IconImage {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: 26
                                    source: Quickshell.iconPath(chip.modelData.icon, "application-x-executable")
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 34
                                    text: chip.modelData.title
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize - 2
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: win.sel = chip.index
                                onClicked: win.activate(chip.modelData)
                            }
                        }
                    }
                }

                // App grid
                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.visibleRows * win.cellH
                    cellWidth: win.cellW
                    cellHeight: win.cellH
                    clip: true
                    model: win.apps
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: true

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: win.sel === win.wins.length + index
                        width: win.cellW
                        height: win.cellH

                        SkewPanel {
                            anchors { fill: parent; margins: 4 }
                            skew: -8
                            fill: cell.selected ? Theme.surface : "transparent"
                            stroke: Theme.accent
                            strokeWidth: cell.selected ? 2 : 0
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitSize: 44
                                source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                            }
                            Text {
                                width: win.cellW - 22
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.title
                                color: cell.selected ? Theme.fg : Theme.fgDim
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: win.sel = win.wins.length + cell.index
                            onClicked: win.activate(cell.modelData)
                        }
                    }
                }
            }

            // Empty state
            Text {
                visible: win.total === 0 && win.wanted
                anchors.centerIn: parent
                text: "No matches"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
            }
        }
    }
}
