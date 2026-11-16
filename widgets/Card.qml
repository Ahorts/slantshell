import QtQuick
import ".."

// Slanted, hard-edged card used by the dashboard and desktop widgets (matches the bar panels).
SkewPanel {
    skew: 8
    fill: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.78)
    stroke: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.35)
    strokeWidth: 1
}
