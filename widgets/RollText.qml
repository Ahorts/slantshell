import QtQuick
import ".."

// Text whose characters roll like an odometer: when a character changes, the old one slides up and out while
// the new one rises in from below (each character on its own, so "09:59" -> "10:00" ripples across).
Row {
    id: rt
    property string text: ""
    property color color: Theme.fg
    property font font: Qt.font({ family: Theme.font, pixelSize: 14 })

    Repeater {
        model: rt.text.length
        Item {
            id: cell
            required property int index
            readonly property string ch: rt.text.charAt(index)
            width: Math.max(cur.implicitWidth, 1)
            height: cur.implicitHeight
            clip: true
            property string shown: ch
            property string old: ""
            onChChanged: { old = shown; shown = ch; roll.restart(); }
            Text { id: prev; text: cell.old; color: rt.color; font: rt.font; y: -cell.height * cell.p; opacity: 1 - cell.p }
            Text { id: cur; text: cell.shown; color: rt.color; font: rt.font; y: cell.height * (1 - cell.p) }
            property real p: 1
            NumberAnimation { id: roll; target: cell; property: "p"; from: 0; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
    }
}
