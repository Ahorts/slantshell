import QtQuick
import ".."

// Translucent rounded card used by the desktop widgets.
Rectangle {
    radius: Theme.radius + 4
    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.78)
    border.color: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.35)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 400 } }
    Behavior on border.color { ColorAnimation { duration: 400 } }
}
