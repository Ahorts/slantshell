import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
import QtQuick

// Wallpaper switcher: a clean carousel of slanted cards, no labels. Left/Right (or scroll) browse,
// Enter applies via skwd-helm and recolours the shell and Hyprland borders, Esc closes.
PanelWindow {
    id: win

    property bool open: false
    signal closeRequested()
    property real appear: 0

    readonly property bool onFocusedScreen: Hyprland.focusedMonitor?.name === screen?.name
    visible: open && onFocusedScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-wallpapers"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    onVisibleChanged: {
        if (visible) {
            appear = 0;
            appearAnim.restart();
            keys.forceActiveFocus();
        }
    }
    NumberAnimation { id: appearAnim; target: win; property: "appear"; to: 1; duration: 420; easing.type: Easing.OutCubic }

    FolderListModel {
        id: files
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Wallpapers"
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    Process { id: applyProc }
    function applyCurrent() {
        const path = files.get(view.currentIndex, "filePath");
        if (!path) return;
        applyProc.command = ["skwd-helm", "apply", path];
        applyProc.running = true;
        Theme.generateFrom(path);   // recolour the shell to match
        closeRequested();
    }

    // Backdrop
    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.55 * win.appear }
    MouseArea { anchors.fill: parent; onClicked: win.closeRequested() }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) win.closeRequested();
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) view.decrementCurrentIndex();
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) view.incrementCurrentIndex();
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) win.applyCurrent();
            else return;
            event.accepted = true;
        }

        WheelHandler {
            onWheel: event => {
                if (event.angleDelta.y > 0 || event.angleDelta.x > 0) view.decrementCurrentIndex();
                else view.incrementCurrentIndex();
            }
        }

        // Carousel
        PathView {
            id: view
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 300
            model: files
            pathItemCount: 9
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: 380
            opacity: win.appear
            // Slide up as it appears.
            transform: Translate { y: (1 - win.appear) * 40 }

            path: Path {
                startX: -120
                startY: view.height / 2
                PathAttribute { name: "s"; value: 0.55 }
                PathAttribute { name: "o"; value: 0.0 }
                PathLine { x: view.width * 0.2; y: view.height / 2 }
                PathAttribute { name: "s"; value: 0.72 }
                PathAttribute { name: "o"; value: 0.7 }
                PathLine { x: view.width / 2; y: view.height / 2 }
                PathAttribute { name: "s"; value: 1.0 }
                PathAttribute { name: "o"; value: 1.0 }
                PathLine { x: view.width * 0.8; y: view.height / 2 }
                PathAttribute { name: "s"; value: 0.72 }
                PathAttribute { name: "o"; value: 0.7 }
                PathLine { x: view.width + 120; y: view.height / 2 }
                PathAttribute { name: "s"; value: 0.55 }
                PathAttribute { name: "o"; value: 0.0 }
            }

            delegate: Item {
                id: card
                required property int index
                required property string filePath
                required property string fileName
                readonly property bool current: PathView.isCurrentItem

                width: 360
                height: 210
                scale: PathView.s
                opacity: PathView.o
                z: current ? 10 : 0

                // Slanted card: shear around the vertical centre so edges lean like "/".
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, -0.2, 0, 0.2 * card.height / 2,
                                         0, 1, 0, 0,
                                         0, 0, 1, 0,
                                         0, 0, 0, 1)
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.bg
                    border.color: card.current ? Theme.accent : Theme.accentContainer
                    border.width: card.current ? 4 : 1
                    Behavior on border.width { NumberAnimation { duration: 200 } }
                }

                Image {
                    anchors { fill: parent; margins: card.current ? 4 : 1 }
                    source: card.filePath ? "file://" + card.filePath : ""
                    sourceSize.width: 520
                    sourceSize.height: 300
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (card.current) win.applyCurrent();
                        else view.currentIndex = card.index;
                    }
                }
            }
        }
    }
}
