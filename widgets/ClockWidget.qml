import Quickshell
import QtQuick
import ".."

// Large desktop clock, date and a greeting.
Column {
    spacing: 0

    SystemClock { id: clock; precision: SystemClock.Minutes }

    readonly property string greeting: {
        const h = clock.date.getHours();
        if (h < 5) return "Still up?";
        if (h < 12) return "Good morning";
        if (h < 18) return "Good afternoon";
        return "Good evening";
    }

    Text {
        text: parent.greeting
        color: Theme.accent
        font.family: Theme.font
        font.pixelSize: 20
        leftPadding: 6
    }

    Text {
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 104
        font.weight: Font.Light
        style: Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.35)
    }

    Text {
        text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: 20
        leftPadding: 6
    }
}
