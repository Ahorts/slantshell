import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import ".."

// Now playing: cover art, title / artist, a live visualizer and playback controls.
// Shows the playing player, or the last one that has a track (paused).
Card {
    id: card

    readonly property var player: Audio.player ?? (Mpris.players.values.find(p => (p.trackTitle ?? "") !== "") ?? null)

    width: 300
    height: 300

    ColumnLayout {
        anchors { fill: parent; margins: 18; leftMargin: 26; rightMargin: 26 }
        spacing: 9

        Text {
            text: "Now playing"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        // Cover art (or a placeholder)
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                border.color: Qt.rgba(Theme.accentContainer.r, Theme.accentContainer.g, Theme.accentContainer.b, 0.5)
                Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "󰎆"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 44
                }
            }
            Image {
                id: art
                anchors { fill: parent; margins: 1 }
                source: card.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }

        // Title and artist
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: card.player ? (card.player.trackTitle || "Unknown track") : "Nothing playing"
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: card.player ? (card.player.trackArtist || card.player.identity || "") : "Play something to see it here"
                color: Theme.fgDim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }

        // Synced lyrics: the line being sung (word by word when the lyrics have word timing) and the next one
        Column {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width
            Layout.preferredHeight: 30
            visible: Lyrics.hasLyrics
            spacing: 2
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.StyledText
                text: Lyrics.line !== "" ? Lyrics.lineHtml : "\u266a"
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.italic: true
                font.bold: true
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Lyrics.next
                color: Theme.fgDim
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        // Live visualizer (when there are no lyrics to show)
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 30
            visible: !Lyrics.hasLyrics
            spacing: 5

            Repeater {
                model: 16

                Rectangle {
                    required property int index
                    readonly property real level: (Audio.bars[index] ?? 0) / 100
                    anchors.bottom: parent.bottom
                    width: 9
                    height: Math.max(3, level * 30)
                    color: Qt.tint(Theme.accent, Qt.rgba(Theme.accent2.r, Theme.accent2.g, Theme.accent2.b, index / 20))
                    Behavior on height { NumberAnimation { duration: 70 } }
                }
            }
        }

        // Controls
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 26
            opacity: card.player ? 1 : 0.35

            Repeater {
                model: [
                    { icon: "󰒮", act: "previous" },
                    { icon: "play", act: "toggle" },
                    { icon: "󰒭", act: "next" }
                ]

                Text {
                    id: btn
                    required property var modelData
                    text: modelData.icon === "play" ? (card.player?.isPlaying ? "󰏤" : "󰐊") : modelData.icon
                    color: area.containsMouse ? Theme.accent : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 24
                    Behavior on color { ColorAnimation { duration: 120 } }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const p = card.player;
                            if (!p) return;
                            if (btn.modelData.act === "previous") p.previous();
                            else if (btn.modelData.act === "next") p.next();
                            else p.togglePlaying();
                        }
                    }
                }
            }
        }
    }
}
