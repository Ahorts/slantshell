import Quickshell
import Quickshell.Wayland
import QtQuick

// Reserves the strip the bar occupies so windows do not slide under it. The island window itself covers the whole
// screen (it can grow into a large panel), and a full-screen layer cannot reserve a strip, so this does.
PanelWindow {
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-desktop-bar-zone"
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    exclusiveZone: 48
    color: "transparent"
    mask: Region {}
}
