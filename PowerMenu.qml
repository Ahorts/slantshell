import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

// Power menu, dead centre: four big slanted bars in a diagonal cascade. They sweep in one after another
// from the left; the selected bar turns solid with a bright "shard" tip. Up/Down or hover to choose, Enter to
// run it. Log out / Restart / Shut down ask once more (Enter again within 4 seconds). Esc closes.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    property real dim: wanted ? 1 : 0
    Behavior on dim { NumberAnimation { duration: 520; easing.type: Easing.InOutQuad } }
    property real prog: wanted ? 1 : 0
    Behavior on prog { NumberAnimation { duration: 900; easing.type: Easing.Linear } }

    visible: wanted || dim > 0.002 || prog > 0.002

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-power"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property string user: Quickshell.env("USER")
    readonly property var items: [
        { label: "LOCK",      sub: "Lock the screen",    icon: "󰌾", cmd: ["loginctl", "lock-session"],            confirm: false },
        { label: "LOG OUT",   sub: "End this session",   icon: "󰍃", cmd: ["loginctl", "terminate-user", win.user], confirm: true },
        { label: "RESTART",   sub: "Reboot the machine", icon: "󰜉", cmd: ["systemctl", "reboot"],                 confirm: true },
        { label: "SHUT DOWN", sub: "Power off",          icon: "󰐥", cmd: ["systemctl", "poweroff"],               confirm: true }
    ]

    property int sel: 0
    property int confirming: -1

    onWantedChanged: {
        if (wanted) {
            sel = 0;
            confirming = -1;
            Qt.callLater(() => keys.forceActiveFocus());
        }
    }
    Timer { id: confirmTimer; interval: 4000; onTriggered: win.confirming = -1 }

    function choose(i) {
        const it = items[i];
        if (it.confirm && confirming !== i) {
            confirming = i;
            confirmTimer.restart();
            return;
        }
        Quickshell.execDetached(it.cmd);
        closeRequested();
    }

    // dim backdrop (its own fade)
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.62 * win.dim }
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (win.confirming >= 0) win.confirming = -1; else win.closeRequested();
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
                win.sel = (win.sel + 1) % win.items.length; win.confirming = -1;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                win.sel = (win.sel + win.items.length - 1) % win.items.length; win.confirming = -1;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                win.choose(win.sel);
            } else return;
            event.accepted = true;
        }
    }

    // ---- the cascade ----
    readonly property real barW: 580
    readonly property real barH: 92
    readonly property real gap: 16
    readonly property real cascade: 38          // each bar sits this much further right than the one above

    Text {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: cascadeHolder.top; bottomMargin: 26 }
        text: "P O W E R"
        color: Theme.accent
        font.family: Theme.font
        font.pixelSize: 18
        font.bold: true
        font.italic: true
        opacity: Math.min(1, win.prog * 2)
    }

    Item {
        id: cascadeHolder
        anchors.centerIn: parent
        width: win.barW + win.cascade * (win.items.length - 1)
        height: win.items.length * win.barH + (win.items.length - 1) * win.gap

        Repeater {
            model: win.items

            SkewPanel {
                id: bar
                required property var modelData
                required property int index
                readonly property bool selected: win.sel === index
                readonly property bool asking: win.confirming === index

                // staggered sweep-in from the left
                readonly property real p: Math.max(0, Math.min(1, (win.prog * 1.6 - index * 0.2)))
                readonly property real e: 1 - Math.pow(1 - p, 3)

                skew: 22
                width: win.barW + (selected ? 56 : 0)
                height: win.barH
                x: index * win.cascade - (1 - e) * 1100
                y: index * (win.barH + win.gap)
                opacity: Math.min(1, e * 2)
                fill: asking ? Theme.warn : (selected ? Theme.accent : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.9))
                stroke: selected ? Theme.accent : Theme.accentContainer
                strokeWidth: selected ? 0 : 1.5
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                // bright shard tip on the selected bar
                SkewPanel {
                    visible: bar.selected
                    x: parent.width - 66
                    y: 0
                    width: 66
                    height: parent.height
                    skew: 22
                    fill: bar.asking ? Qt.lighter(Theme.warn, 1.3) : Theme.accentContainer
                    strokeWidth: 0
                }

                Row {
                    anchors { left: parent.left; leftMargin: 52; verticalCenter: parent.verticalCenter }
                    spacing: 22

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.modelData.icon
                        color: bar.selected ? Theme.accentText : Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 38
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            text: bar.asking ? "CONFIRM?" : bar.modelData.label
                            color: bar.selected ? Theme.accentText : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 38
                            font.bold: true
                            font.italic: true
                            font.letterSpacing: 3
                        }
                        Text {
                            text: bar.asking ? "Enter to confirm  ·  Esc to cancel" : bar.modelData.sub
                            color: bar.selected ? Qt.rgba(Theme.accentText.r, Theme.accentText.g, Theme.accentText.b, 0.75) : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.italic: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: { win.sel = bar.index; if (win.confirming !== bar.index) win.confirming = -1; }
                    onClicked: win.choose(bar.index)
                }
            }
        }
    }
}
