import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import ".."

// System card: CPU / RAM / disk / battery rings plus uptime.
Card {
    id: card

    property real cpu: 0
    property real mem: 0
    property real disk: 0
    property string uptime: ""
    property var _prev: null

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isPresent && battery.isLaptopBattery

    width: 300
    height: col.implicitHeight + 36

    function parseStat(t) {
        const f = t.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + (f[4] || 0);
        const total = f.reduce((a, b) => a + b, 0);
        if (_prev) {
            const dt = total - _prev.total, di = idle - _prev.idle;
            if (dt > 0) cpu = Math.max(0, Math.min(1, 1 - di / dt));
        }
        _prev = { total: total, idle: idle };
    }

    function parseMem(t) {
        const get = k => Number((t.match(new RegExp(k + ":\\s+(\\d+)")) || [0, 0])[1]);
        const total = get("MemTotal"), avail = get("MemAvailable");
        if (total > 0) mem = 1 - avail / total;
    }

    function parseUptime(t) {
        const s = Math.floor(Number(t.split(" ")[0]));
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        uptime = "up " + (d > 0 ? d + "d " : "") + h + "h " + m + "m";
    }

    FileView { id: statFile; path: "/proc/stat"; onLoaded: card.parseStat(text()) }
    FileView { id: memFile; path: "/proc/meminfo"; onLoaded: card.parseMem(text()) }
    FileView { id: upFile; path: "/proc/uptime"; onLoaded: card.parseUptime(text()) }

    Process {
        id: dfProc
        command: ["df", "--output=pcent", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)%/);
                if (m) card.disk = Number(m[1]) / 100;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { statFile.reload(); memFile.reload(); upFile.reload(); }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: dfProc.running = true
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 18 }
        spacing: 10

        Text {
            text: "System"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 2
            columnSpacing: 22
            rowSpacing: 10

            LiquidOrb { value: card.cpu; color: Theme.accent; label: "CPU" }
            LiquidOrb { value: card.mem; color: Theme.accent2; label: "RAM" }
            LiquidOrb { value: card.disk; color: card.disk > 0.9 ? Theme.warn : Theme.accentContainer; label: "Disk" }
            LiquidOrb {
                visible: card.hasBattery
                value: card.hasBattery ? card.battery.percentage : 0
                color: card.hasBattery && card.battery.percentage < 0.2 ? Theme.warn : Theme.good
                label: card.hasBattery && card.battery.state === UPowerDeviceState.Charging ? "Charging" : "Battery"
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: card.uptime
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
