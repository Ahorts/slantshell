import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// App switcher / selector overlay.
// Lists open windows (select = switch to it) and installed apps (select = launch it).
// Type to filter. Up/Down (or Ctrl+N/P/J/K) move, Enter selects, Esc closes.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    // Only show on the monitor that currently has focus.
    readonly property bool onFocusedScreen: Hyprland.focusedMonitor?.name === screen?.name
    visible: open && onFocusedScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            input.text = "";
            list.currentIndex = 0;
            input.forceActiveFocus();
        }
    }

    // ---- Data ----
    function score(item, q) {
        const name = item.title.toLowerCase();
        let s;
        if (name.startsWith(q)) s = 0;
        else if (name.includes(" " + q)) s = 1;
        else if (name.includes(q)) s = 2;
        else if (item.extra.includes(q)) s = 3;
        else return -1;
        return item.kind === "window" ? s - 0.5 : s;
    }

    readonly property var results: {
        if (!visible) return [];
        const q = input.text.trim().toLowerCase();
        const items = [];

        for (const t of ToplevelManager.toplevels.values) {
            const entry = DesktopEntries.heuristicLookup(t.appId);
            items.push({
                kind: "window",
                title: t.title || t.appId,
                subtitle: "Window · " + t.appId,
                extra: (t.appId + " " + t.title).toLowerCase(),
                icon: entry ? entry.icon : t.appId,
                ref: t
            });
        }

        const apps = [];
        for (const a of DesktopEntries.applications.values) {
            if (a.noDisplay) continue;
            apps.push({
                kind: "app",
                title: a.name,
                subtitle: a.comment || a.genericName || "Application",
                extra: ((a.genericName || "") + " " + (a.comment || "") + " " + (a.keywords || []).join(" ")).toLowerCase(),
                icon: a.icon,
                ref: a
            });
        }
        apps.sort((x, y) => x.title.localeCompare(y.title));

        const all = items.concat(apps);
        if (q === "") return all.slice(0, 60);

        return all
            .map(i => ({ i: i, s: score(i, q) }))
            .filter(x => x.s >= 0)
            .sort((a, b) => a.s - b.s)
            .map(x => x.i)
            .slice(0, 60);
    }

    function activate(item) {
        if (!item) return;
        if (item.kind === "window") item.ref.activate();
        else item.ref.execute();
        closeRequested();
    }

    // ---- UI ----
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.4 }
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

    Rectangle {
        id: card
        width: 640
        height: Math.min(560, header.height + list.contentHeight + 28)
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        radius: Theme.radius + 6
        color: Theme.bgAlt
        border.color: Theme.surface
        border.width: 1

        MouseArea { anchors.fill: parent } // swallow clicks so the backdrop doesn't close us

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            Rectangle {
                id: header
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Theme.radius
                color: Theme.surface

                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    selectionColor: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 4
                    clip: true
                    focus: true

                    onTextChanged: list.currentIndex = 0

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        if (event.key === Qt.Key_Escape) {
                            win.closeRequested();
                        } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
                            list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1);
                        } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
                            list.currentIndex = Math.max(0, list.currentIndex - 1);
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.activate(win.results[list.currentIndex]);
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        visible: input.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search windows and apps…"
                        color: Theme.fgDim
                        font: input.font
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: win.results
                currentIndex: 0
                highlightMoveDuration: 80
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 48
                    radius: Theme.radius - 2
                    color: ListView.isCurrentItem ? Theme.surface : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 12

                        IconImage {
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            implicitSize: 30
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: Theme.fg
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize + 1
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.subtitle
                                color: Theme.fgDim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }

                        Text {
                            visible: row.modelData.kind === "window"
                            text: "open"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: list.currentIndex = row.index
                        onClicked: win.activate(row.modelData)
                    }
                }
            }
        }
    }
}
