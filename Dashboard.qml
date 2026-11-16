import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "widgets"

// Dashboard drawer: the island morphs into it. The panel starts as the island (same spot, same slant),
// widens first with a little spring, grows downward a beat later, and only then do the cards fade in.
// Closing runs it backwards, shrinking into the island. Open it by clicking the clock, or
// `ipc call dashboard toggle`. It closes by itself shortly after the pointer leaves it.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()

    readonly property bool onFocusedScreen: Hyprland.focusedMonitor?.name === screen?.name
    readonly property bool wanted: open && onFocusedScreen
    property bool everHovered: false

    // Two separate progress values so the shape morphs instead of just scaling:
    // width springs out first, height follows slightly later.
    property real pw: wanted ? 1 : 0
    property real ph: wanted ? 1 : 0
    Behavior on pw { NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
    Behavior on ph {
        SequentialAnimation {
            PauseAnimation { duration: win.wanted ? 90 : 0 }
            NumberAnimation { duration: win.wanted ? 560 : 380; easing.type: Easing.OutCubic }
        }
    }

    visible: wanted || pw > 0.002 || ph > 0.002
    onWantedChanged: if (wanted) everHovered = false

    // The island's resting size and position (see Island.qml): centred, top margin 8, 40 high.
    readonly property real startW: 230
    readonly property real startH: 40
    readonly property real topGap: 8
    // Content fades in only once the shape has mostly formed (and out first when closing).
    readonly property real contentOpacity: Math.max(0, Math.min(1, (ph - 0.6) / 0.35))

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-desktop-dashboard"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true }
    implicitWidth: content.implicitWidth + 64 + 70
    implicitHeight: content.implicitHeight + 44 + 40
    color: "transparent"
    mask: Region { item: panel }

    SkewPanel {
        id: panel
        glass: true
        glassOriginX: Math.round((win.screen.width - win.width) / 2)
        skewL: -(14 + 2 * win.ph)
        skewR: 14 + 2 * win.ph   // same trapezoid as the island it grows out of (wider at the top)
        clip: true
        // Quick fade-in so the first frames read as "the island, growing".
        opacity: Math.min(1, win.pw * 8)
        width: win.startW + (content.implicitWidth + 64 - win.startW) * win.pw
        height: win.startH + (content.implicitHeight + 44 - win.startH) * win.ph
        x: Math.round((win.width - width) / 2)
        y: win.topGap

        HoverHandler {
            id: hov
            onHoveredChanged: if (hovered) win.everHovered = true
        }

        Row {
            id: content
            anchors.horizontalCenter: parent.horizontalCenter
            y: 22
            spacing: 16
            opacity: win.contentOpacity
            scale: 0.95 + 0.05 * win.contentOpacity
            transformOrigin: Item.Top

            CalendarWidget { height: 300 }
            MediaWidget {}
            // Usage gauges only poll while the dashboard is up.
            Loader {
                active: win.visible
                width: 300
                height: item ? item.height : 190
                sourceComponent: StatsWidget {}
                onLoaded: item.height = 300
            }
        }
    }

    // Close shortly after the pointer leaves (a longer grace if it was never over the panel).
    Timer {
        interval: win.everHovered ? 900 : 3500
        running: win.open && !hov.hovered
        onTriggered: win.closeRequested()
    }
}
