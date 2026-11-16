import Quickshell
import QtQuick
import QtQuick.Layouts
import ".."

// Month calendar (weeks start on Monday) with today highlighted.
Card {
    id: card

    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property var now: clock.date
    readonly property int year: now.getFullYear()
    readonly property int month: now.getMonth()
    readonly property int today: now.getDate()
    // Monday-first offset of the 1st of the month (0..6).
    readonly property int offset: (new Date(year, month, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()

    width: 7 * 36 + 32
    height: col.implicitHeight + 32

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 16 }
        spacing: 8

        Text {
            text: Qt.formatDateTime(card.now, "MMMM yyyy")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        GridLayout {
            columns: 7
            rowSpacing: 4
            columnSpacing: 0

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Text {
                    required property string modelData
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Repeater {
                model: 42

                Item {
                    id: cell
                    required property int index
                    readonly property int day: index - card.offset + 1
                    readonly property bool valid: day >= 1 && day <= card.daysInMonth
                    readonly property bool isToday: valid && day === card.today

                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 28

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.accent
                        visible: cell.isToday
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.valid
                        text: cell.day
                        color: cell.isToday ? Theme.accentText : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: cell.isToday
                    }
                }
            }
        }
    }
}
