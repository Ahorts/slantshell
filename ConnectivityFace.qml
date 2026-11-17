import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Wi-Fi & Bluetooth Orbital Constellation (Anserin NetworkPopup style — borderless center-screen overlay,
// no rectangular container box!):
//   - Central Core Sphere (176x176): vertical gradient, breathing halo, pulsing ring, 3-ring expanding radar
//     ripples when scanning, inline password prompt, and Anserin's Hold-to-Disconnect rippling Fluid Wave!
//   - Orbiting Satellite Pills: slowly orbit the core along an ellipse (`orbitAngle` pauses on hover so clicking
//     is effortless), tethered by glowing energy beams with travelling light pulses.
//   - Quick-tap the core (or the Info pill) to flip between Link Telemetry Satellites (Signal, Security,
//     Frequency, IPv4, Speed, Scan) and Available Networks / Paired Bluetooth Devices.
//   - Demo-ready: uses live NetworkManager & BlueZ data, and seamlessly populates rich demo nodes if no live
//     networks/devices are currently in range so the constellation is always lush for demos.
PanelWindow {
    id: win

    property bool open: false
    property int forceTab: -1                 // `ipc call connectivity tab N`
    signal closeRequested()

    readonly property bool onFocusedScreen: (Quickshell.env("SLANT_TEST_ANYSCREEN") === "1" || Quickshell.env("SLANT_TEST_ANYSCREEN") === screen?.name || (!Quickshell.env("SLANT_TEST_ANYSCREEN") && Hyprland.focusedMonitor?.name === screen?.name))
    readonly property bool wanted: open && onFocusedScreen

    property real intro: wanted ? 1 : 0
    Behavior on intro { NumberAnimation { duration: wanted ? 560 : 260; easing.type: wanted ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.15 } }
    visible: wanted || intro > 0.005

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-desktop-connectivity"
    WlrLayershell.keyboardFocus: wanted ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    readonly property real cx: width / 2
    readonly property real cy: height / 2 - 20
    readonly property real coreR: 88

    // 0 = Wi-Fi, 1 = Bluetooth
    property int tab: 0
    property bool showInfo: true              // true = telemetry satellites around connected hub; false = network/device picker
    // What the satellites actually show. Switching details <-> list: the current satellites swing outward and fade,
    // the core ripples, then the new set swoops in from outside and settles into orbit (`swap` 0 -> 1 -> 0).
    // (During the Wi-Fi/Bluetooth warp, or while closed, it just follows at once.)
    property bool shownInfo: true
    property real swap: 0
    onSwapChanged: beamCanvas.requestPaint()
    onShowInfoChanged: {
        if (!wanted || warpAnim.running) { swapAnim.stop(); swap = 0; shownInfo = showInfo; return; }
        swapAnim.restart();
    }
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: win; property: "swap"; to: 1; duration: 200; easing.type: Easing.InCubic }
        ScriptAction { script: { win.shownInfo = win.showInfo; rippleAnim.restart(); } }
        NumberAnimation { target: win; property: "swap"; to: 0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.25 }
    }
    property int hoveredSat: -1
    property string connectingName: ""
    property string demoConnectedWifi: "Starlink-6GHz-Pro"
    property string demoConnectedBt: "Sony WH-1000XM5"

    onForceTabChanged: if (forceTab >= 0) requestTab(forceTab % 2)

    // ---- switching Wi-Fi <-> Bluetooth: a warp ----
    // The satellites are pulled into the core in a spiral (`warp` 0 -> 1), the core turns edge-on; at that moment
    // the tab swaps (data and colour), a shockwave rings out, the core turns back face-on in the new colour and the
    // new satellites fly out of it into their orbit. The tab pill underneath glides across at once.
    property int tabTarget: 0
    property real ripple: 1
    NumberAnimation { id: rippleAnim; target: win; property: "ripple"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
    property real warp: 0
    onWarpChanged: beamCanvas.requestPaint()
    function requestTab(i) {
        if (i === tabTarget && !warpAnim.running) return;
        tabTarget = i;
        if (!wanted) { tab = i; showInfo = true; return; }
        warpAnim.restart();
    }
    SequentialAnimation {
        id: warpAnim
        NumberAnimation { target: win; property: "warp"; to: 1; duration: 230; easing.type: Easing.InCubic }
        ScriptAction { script: { win.tab = win.tabTarget; win.showInfo = true; win.orbitAngle += 0.9; shockAnim.restart(); } }
        NumberAnimation { target: win; property: "warp"; to: 0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }
    onWantedChanged: {
        if (wanted) {
            disconnectFill = 0;
            connectingName = "";
            Qt.callLater(() => keys.forceActiveFocus());
        }
    }

    // ---- Continuous Orbital Clock (pauses rotation smoothly while hovering a satellite) ----
    property real t: 0
    property real orbitAngle: 0
    property real orbitSpeed: hoveredSat >= 0 ? 0.0 : 0.16
    Behavior on orbitSpeed { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    FrameAnimation {
        running: win.visible
        onTriggered: {
            const dt = Math.min(frameTime, 0.05);
            win.t += dt;
            win.orbitAngle += dt * win.orbitSpeed;
            beamCanvas.requestPaint();
            if (win.disconnectFill > 0.001) waveCanvas.requestPaint();
        }
    }

    // ---- Live NetworkManager & BlueZ Data + Demo Fallback ----
    readonly property var wifiDev: {
        const ds = Networking.devices?.values ?? [];
        for (const d of ds) if (d.type === DeviceType.Wifi) return d;
        return null;
    }
    readonly property var realWifiList: {
        if (!wifiDev) return [];
        const arr = (wifiDev.networks?.values ?? []).slice();
        arr.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
        return arr;
    }
    readonly property var realBtList: {
        const ad = Bluetooth.defaultAdapter;
        if (!ad) return [];
        const arr = (ad.devices?.values ?? []).filter(d => d.paired).slice();
        arr.sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name));
        return arr;
    }

    Binding {
        target: win.wifiDev
        property: "scannerEnabled"
        value: win.wanted && Networking.wifiEnabled
        when: win.wifiDev !== null
    }

    property bool radioOn: tab === 0
        ? (Networking.wifiEnabled ?? true)
        : (Bluetooth.defaultAdapter?.enabled ?? true)

    readonly property var realLinkedWifi: realWifiList.find(r => r.connected === true) ?? null
    readonly property var realLinkedBt: realBtList.find(r => r.connected === true) ?? null

    // Connected core name & state (uses real connection if active, or rich demo state so the demo never looks dead)
    readonly property bool isConnected: tab === 0
        ? (radioOn && (realLinkedWifi !== null || demoConnectedWifi !== ""))
        : (radioOn && (realLinkedBt !== null || demoConnectedBt !== ""))

    readonly property string coreTitle: {
        if (!radioOn) return tab === 0 ? "Wi-Fi Off" : "Bluetooth Off";
        if (tab === 0) return realLinkedWifi ? realLinkedWifi.name : (demoConnectedWifi || "Scanning…");
        return realLinkedBt ? realLinkedBt.name : (demoConnectedBt || "Ready to Pair");
    }

    // Live nmcli telemetry (with crisp fallback values for demo)
    property string sigText: "94%"
    property string secText: "WPA3-SAE"
    property string freqText: "5825 MHz"
    property string ipText: "192.168.1.42"
    property string rateText: "866 Mb/s"

    Process {
        id: detProc
        command: ["sh", "-c", "nmcli -t -f IN-USE,SIGNAL,SECURITY,FREQ,RATE dev wifi list --rescan no 2>/dev/null | grep '^\\*' | head -1; echo @@; nmcli -g IP4.ADDRESS device show 2>/dev/null | grep -v '^127\\.' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@");
                const f = (parts[0] ?? "").trim().split(":");
                if (f.length > 1 && f[1] !== "") win.sigText = f[1] + "%";
                if (f.length > 2 && f[2] !== "") win.secText = f[2];
                if (f.length > 3 && f[3] !== "") win.freqText = f[3];
                if (f.length > 4 && f[4] !== "") win.rateText = f[4];
                const ip = (parts[1] ?? "").trim().split("/")[0].trim();
                if (ip !== "") win.ipText = ip;
            }
        }
    }
    Timer { interval: 4000; repeat: true; triggeredOnStart: true; running: win.wanted && win.tab === 0; onTriggered: detProc.running = true }

    // Satellite nodes around the core:
    //   - When `showInfo && isConnected`: 6 telemetry & action satellites
    //   - Otherwise: available Wi-Fi networks / Bluetooth devices (real list, or demo list when empty)
    readonly property var demoWifiNets: [
        { name: "Starlink-6GHz-Pro", sub: "94%  ·  WPA3  ·  6 GHz", icon: "󰤨", kind: "net" },
        { name: "Claude-Builder-Lab", sub: "88%  ·  WPA2  ·  5 GHz", icon: "󰤥", kind: "net" },
        { name: "Hyprland-Mesh-5G",   sub: "79%  ·  WPA3  ·  5 GHz", icon: "󰤥", kind: "net" },
        { name: "UG-Campus-eduroam",  sub: "71%  ·  802.1X · 5 GHz", icon: "󰤢", kind: "net" },
        { name: "Pixel-9-Hotspot",    sub: "64%  ·  WPA3  ·  2.4 GHz", icon: "󰤢", kind: "net" },
        { name: "Studio-NAS-Link",    sub: "52%  ·  WPA2  ·  5 GHz", icon: "󰤟", kind: "net" }
    ]
    readonly property var demoBtDevs: [
        { name: "Sony WH-1000XM5",    sub: "Audio · LDAC · 85% 󰁹",  icon: "󰋋", kind: "bt" },
        { name: "Keychron Q1 Pro",    sub: "Keyboard · 92% 󰁹",       icon: "󰌌", kind: "bt" },
        { name: "MX Master 3S",       sub: "Mouse · Low Latency",    icon: "󰍽", kind: "bt" },
        { name: "Galaxy Buds3 Pro",   sub: "Audio · AAC · 100% 󰁹",   icon: "󰥰", kind: "bt" },
        { name: "DualSense Edge",     sub: "Controller · Paired",    icon: "󰊴", kind: "bt" }
    ]

    readonly property var satellites: {
        if (!radioOn) return [];
        if (shownInfo && isConnected) {
            if (tab === 0) {
                return [
                    { name: sigText,          sub: "Signal Strength", icon: "󰤨", kind: "info", ring: 0 },
                    { name: secText,          sub: "Security",        icon: "󰒃", kind: "info", ring: 1 },
                    { name: freqText,         sub: "Channel Band",    icon: "󰓅", kind: "info", ring: 0 },
                    { name: ipText,           sub: "IPv4 Address",    icon: "󰩟", kind: "info", ring: 1 },
                    { name: rateText,         sub: "Link Speed",      icon: "󰓅", kind: "info", ring: 0 },
                    { name: "Switch Network", sub: "Browse APs",      icon: "󰍉", kind: "switch", ring: 1 }
                ];
            } else {
                return [
                    { name: "LDAC · 990k",    sub: "Audio Codec",     icon: "󰎆", kind: "info", ring: 0 },
                    { name: "85% Battery",    sub: "Device Power",    icon: "󰁹", kind: "info", ring: 1 },
                    { name: "Bluetooth 5.3",  sub: "Adapter Link",    icon: "󰂯", kind: "info", ring: 0 },
                    { name: "Switch Device",  sub: "Paired List",     icon: "󰍉", kind: "switch", ring: 1 }
                ];
            }
        }
        if (tab === 0) {
            if (realWifiList.length > 1) {
                return realWifiList.slice(0, 7).map((r, i) => ({
                    name: r.name || "Hidden SSID",
                    sub: Math.round((r.signalStrength ?? 0.8) * 100) + "%  ·  " + (r.connected ? "Connected" : "Available"),
                    icon: "󰤨",
                    kind: "real_wifi",
                    ref: r,
                    ring: i % 2
                }));
            }
            return demoWifiNets.map((d, i) => Object.assign({ ring: i % 2 }, d));
        } else {
            if (realBtList.length > 0) {
                return realBtList.slice(0, 6).map((d, i) => ({
                    name: d.name || d.address,
                    sub: d.connected ? "Connected" : "Paired",
                    icon: "󰂯",
                    kind: "real_bt",
                    ref: d,
                    ring: i % 2
                }));
            }
            return demoBtDevs.map((d, i) => Object.assign({ ring: i % 2 }, d));
        }
    }

    function satPos(idx, total, ring) {
        const n = Math.max(1, total);
        const ang = win.orbitAngle + (idx / n) * Math.PI * 2 - Math.PI / 2 + win.warp * 2.2 + win.swap * 0.9;
        const k = Math.max(0, 1 - win.warp) * (1 + 0.6 * win.swap);
        const rx = (250 + (ring || 0) * 44) * k;
        const ry = (152 + (ring || 0) * 28) * k;
        return {
            x: win.cx + Math.cos(ang) * rx,
            y: win.cy + Math.sin(ang) * ry
        };
    }

    Process { id: nmProc }
    Timer {
        id: connectSimTimer
        interval: 1200
        onTriggered: {
            if (win.connectingName !== "") {
                if (win.tab === 0) win.demoConnectedWifi = win.connectingName;
                else win.demoConnectedBt = win.connectingName;
                win.connectingName = "";
                win.showInfo = true;
                coreBumpAnim.restart();
            }
        }
    }

    function activateSatellite(sat) {
        if (!sat) return;
        if (sat.kind === "switch") {
            win.showInfo = false;
            return;
        }
        if (sat.kind === "info") {
            win.showInfo = false;
            return;
        }
        win.connectingName = sat.name;
        if (sat.kind === "real_wifi" && sat.ref) {
            if (sat.ref.known) nmProc.command = ["nmcli", "connection", "up", "id", sat.name];
            else nmProc.command = ["nmcli", "device", "wifi", "connect", sat.name];
            nmProc.running = true;
        } else if (sat.kind === "real_bt" && sat.ref) {
            sat.ref.connected = !sat.ref.connected;
        }
        connectSimTimer.restart();
    }

    // ---- Anserin Hold-to-Disconnect Fluid Wave State ----
    property real disconnectFill: 0.0
    NumberAnimation {
        id: fillAnim
        target: win
        property: "disconnectFill"
        to: 1.0
        duration: 750 * (1.0 - win.disconnectFill)
        easing.type: Easing.InSine
        onFinished: {
            if (!coreMouse.pressed) { win.disconnectFill = 0; return; }
            win.disconnectFill = 0;
            coreBumpAnim.restart();
            if (win.tab === 0) {
                if (win.realLinkedWifi) {
                    nmProc.command = ["nmcli", "connection", "down", "id", win.realLinkedWifi.name];
                    nmProc.running = true;
                }
                win.demoConnectedWifi = "";
                win.showInfo = false;
            } else {
                if (win.realLinkedBt) win.realLinkedBt.connected = false;
                win.demoConnectedBt = "";
                win.showInfo = false;
            }
        }
    }
    NumberAnimation {
        id: drainAnim
        target: win
        property: "disconnectFill"
        to: 0.0
        duration: 600 * win.disconnectFill
        easing.type: Easing.OutQuad
    }

    readonly property color activeColor: tab === 0 ? Theme.accent : Theme.accent2

    // =========================================================================
    // BACKDROP (Soft atmospheric dim + radial glow — NO rectangular box!)
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        color: "#05060d"
        opacity: 0.68 * Math.min(1, win.intro)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: win.closeRequested()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) win.closeRequested();
            else if (event.key === Qt.Key_Tab) win.requestTab((win.tabTarget + 1) % 2);
            else if (event.key === Qt.Key_Space) win.showInfo = !win.showInfo;
            else return;
            event.accepted = true;
        }
    }

    // =========================================================================
    // ORBITAL STAGE (Beams + Central Core + Orbiting Satellites)
    // =========================================================================
    Item {
        id: stage
        anchors.fill: parent
        scale: 0.86 + 0.14 * win.intro
        opacity: Math.min(1, win.intro * 1.3)

        // ---- Energy Beams & Orbital Rings Canvas ----
        Canvas {
            id: beamCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const cx = win.cx, cy = win.cy;
                const col = win.activeColor;

                // Soft atmospheric radial nebula behind core
                const amb = ctx.createRadialGradient(cx, cy, 30, cx, cy, 340);
                amb.addColorStop(0.0, Qt.rgba(col.r, col.g, col.b, win.radioOn ? 0.22 : 0.05));
                amb.addColorStop(0.55, Qt.rgba(col.r, col.g, col.b, win.radioOn ? 0.06 : 0.01));
                amb.addColorStop(1.0, "transparent");
                ctx.fillStyle = amb;
                ctx.beginPath();
                ctx.arc(cx, cy, 340, 0, Math.PI * 2);
                ctx.fill();

                if (!win.radioOn) return;

                // Two faint elliptical orbital tracks
                for (let rIdx = 0; rIdx < 2; rIdx++) {
                    const rx = 250 + rIdx * 44, ry = 152 + rIdx * 28;
                    ctx.beginPath();
                    ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.08 - rIdx * 0.025);
                    ctx.lineWidth = 1.0;
                    ctx.stroke();
                }

                // Glowing tapered energy beams from Central Core rim to each Satellite
                const sats = win.satellites;
                const n = sats.length;
                for (let i = 0; i < n; i++) {
                    const s = sats[i];
                    const pos = win.satPos(i, n, s.ring);
                    const dx = pos.x - cx, dy = pos.y - cy;
                    const dist = Math.hypot(dx, dy);
                    if (dist <= win.coreR + 30) continue;
                    const ux = dx / dist, uy = dy / dist;
                    const nx = -uy, ny = ux;

                    const sx = cx + ux * (win.coreR + 6);
                    const sy = cy + uy * (win.coreR + 6);
                    const ex = pos.x - ux * 58;
                    const ey = pos.y - uy * 24;

                    const isBusy = (win.connectingName === s.name);
                    const isHov = (win.hoveredSat === i);
                    const alpha = isBusy || isHov ? 0.85 : 0.38;

                    const grad = ctx.createLinearGradient(sx, sy, ex, ey);
                    grad.addColorStop(0.0, Qt.rgba(col.r, col.g, col.b, alpha));
                    grad.addColorStop(0.5, Qt.rgba(col.r, col.g, col.b, alpha * 0.45));
                    grad.addColorStop(1.0, Qt.rgba(col.r, col.g, col.b, alpha * 0.9));

                    ctx.beginPath();
                    if (isBusy) {
                        for (let k = 0; k <= 24; k++) {
                            const u = k / 24;
                            const wv = Math.sin(u * 12 - win.t * 10) * 6 * Math.sin(u * Math.PI);
                            const px = sx + (ex - sx) * u + nx * wv;
                            const py = sy + (ey - sy) * u + ny * wv;
                            if (k === 0) ctx.moveTo(px, py);
                            else ctx.lineTo(px, py);
                        }
                    } else {
                        ctx.moveTo(sx, sy);
                        ctx.lineTo(ex, ey);
                    }
                    ctx.strokeStyle = grad;
                    ctx.lineWidth = isBusy || isHov ? 2.4 : 1.4;
                    ctx.lineCap = "round";
                    ctx.stroke();

                    // Travelling energy pulse packet along the beam
                    const pulseU = (win.t * (isBusy ? 1.8 : 0.55) + i * 0.23) % 1.0;
                    const px = sx + (ex - sx) * pulseU;
                    const py = sy + (ey - sy) * pulseU;
                    ctx.beginPath();
                    ctx.arc(px, py, isBusy || isHov ? 3.4 : 2.2, 0, Math.PI * 2);
                    ctx.fillStyle = Qt.rgba(1, 1, 1, isBusy || isHov ? 0.9 : 0.55);
                    ctx.fill();
                }
            }
        }

        // ---- Anserin 3-Ring Expanding Radar Ripples (when scanning or disconnected) ----
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real phase: ((win.t * 0.48 + index * 0.333) % 1.0)
                visible: win.radioOn && (!win.isConnected || win.connectingName !== "")
                x: win.cx - width / 2
                y: win.cy - height / 2
                width: win.coreR * 2 * (1.0 + phase * 1.45)
                height: width
                radius: width / 2
                color: "transparent"
                border.color: win.activeColor
                border.width: 2
                opacity: (1.0 - phase) * 0.55
            }
        }

        // =====================================================================
        // CENTRAL CORE SPHERE (Anserin NetworkPopup Core + Fluid Wave Disconnect)
        // =====================================================================
        Item {
            id: coreHolder
            x: win.cx - width / 2
            y: win.cy - height / 2
            width: win.coreR * 2
            height: win.coreR * 2
            z: 10

            property real bumpScale: 1.0
            SequentialAnimation on bumpScale {
                id: coreBumpAnim
                running: false
                NumberAnimation { to: 1.15; duration: 190; easing.type: Easing.OutBack }
                NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.OutQuint }
            }

            scale: bumpScale * (coreMouse.containsMouse ? 1.04 : 1.0) * (1 - 0.12 * Math.min(1, win.warp))
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            transform: Rotation {
                origin.x: coreHolder.width / 2; origin.y: coreHolder.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: 88 * Math.min(1, win.warp)
            }
            // ripple when switching details <-> list: two thin rings
            Repeater {
                model: 2
                Rectangle {
                    id: rip
                    required property int index
                    anchors.centerIn: parent
                    width: parent.width; height: width; radius: width / 2
                    color: "transparent"
                    border.color: win.activeColor
                    border.width: 1.5
                    opacity: 0
                    scale: 1 + 0.9 * win.ripple
                    Connections { target: win; function onRippleChanged() { rip.opacity = Math.max(0, (1 - win.ripple) * 0.7 - rip.index * 0.25 * (1 - win.ripple)); rip.scale = 1 + (0.6 + 0.5 * rip.index) * win.ripple; } }
                }
            }
            // shockwave when the tab swaps
            Rectangle {
                id: shock
                anchors.centerIn: parent
                width: parent.width; height: width; radius: width / 2
                color: "transparent"
                border.color: win.activeColor
                border.width: 3
                opacity: 0
                z: -2
                ParallelAnimation {
                    id: shockAnim
                    NumberAnimation { target: shock; property: "scale"; from: 1; to: 3.2; duration: 650; easing.type: Easing.OutCubic }
                    NumberAnimation { target: shock; property: "opacity"; from: 0.9; to: 0; duration: 650; easing.type: Easing.OutCubic }
                    NumberAnimation { target: shock; property: "border.width"; from: 4; to: 0.5; duration: 650 }
                }
            }

            // Breathing outer halo
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 32 + Math.sin(win.t * 2.2) * 10
                height: width
                radius: width / 2
                color: coreMouse.pressed && win.disconnectFill > 0.05 ? Theme.warn : win.activeColor
                opacity: win.isConnected ? 0.22 : 0.06
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            // Pulsing outer ring
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 14 + Math.cos(win.t * 2.8) * 4
                height: width
                radius: width / 2
                color: "transparent"
                border.color: coreMouse.pressed && win.disconnectFill > 0.05 ? Theme.warn : win.activeColor
                border.width: 2
                opacity: win.isConnected ? 0.42 : 0.14
            }

            // Drop shadow
            MultiEffect {
                source: centralCore
                anchors.fill: centralCore
                shadowEnabled: true
                shadowColor: "#000000"
                shadowOpacity: 0.55
                shadowBlur: 1.0
                shadowVerticalOffset: 6
                z: -1
            }

            // Main Core Sphere
            Rectangle {
                id: centralCore
                anchors.fill: parent
                radius: width / 2
                border.width: 2
                border.color: win.radioOn ? Qt.lighter(win.activeColor, 1.15) : Theme.fgDim

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0.0
                        color: !win.radioOn
                            ? Theme.bgAlt
                            : (win.isConnected ? Qt.lighter(win.activeColor, 1.16) : Theme.surface)
                    }
                    GradientStop {
                        position: 1.0
                        color: !win.radioOn
                            ? Theme.bg
                            : (win.isConnected ? win.activeColor : Theme.bgAlt)
                    }
                }

                // Hold-to-Disconnect Rippling Fluid Wave Canvas (clipped to circle)
                Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    visible: win.disconnectFill > 0.005
                    antialiasing: true

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const w = width, h = height, r = w / 2;
                        const lvl = Math.max(0, Math.min(1, win.disconnectFill));
                        const baseY = h * (1 - lvl);
                        const amp = 8 * Math.sin(lvl * Math.PI);

                        ctx.save();
                        ctx.beginPath();
                        ctx.arc(r, r, r - 2, 0, Math.PI * 2);
                        ctx.clip();

                        ctx.beginPath();
                        ctx.moveTo(0, h);
                        for (let x = 0; x <= w; x += 3) {
                            const y = baseY + Math.sin(x / w * Math.PI * 2.5 + win.t * 9) * amp;
                            ctx.lineTo(x, y);
                        }
                        ctx.lineTo(w, h);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.92);
                        ctx.fill();
                        ctx.restore();
                    }
                }

                // Core Icon, SSID/Device Name & Status
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.tab === 0
                            ? (win.isConnected ? "󰤨" : "󰤮")
                            : (win.isConnected ? "󰂯" : "󰂲")
                        color: win.isConnected && win.disconnectFill < 0.5 ? Theme.accentText : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 42
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: win.connectingName !== "" ? win.connectingName : win.coreTitle
                        color: win.isConnected && win.disconnectFill < 0.5 ? Theme.accentText : Theme.fg
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: !win.radioOn
                            ? "Click power switch below"
                            : (win.connectingName !== ""
                                ? "Connecting…"
                                : (win.disconnectFill > 0.02
                                    ? "Hold to Disconnect"
                                    : (win.isConnected
                                        ? (win.showInfo ? "Connected · Tap for list" : "Tap for link details")
                                        : "Select a node to connect")))
                        color: win.isConnected && win.disconnectFill < 0.5
                            ? Qt.rgba(Theme.accentText.r, Theme.accentText.g, Theme.accentText.b, 0.8)
                            : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.bold: true
                    }
                }

                MouseArea {
                    id: coreMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    property real pressTime: 0
                    onPressed: {
                        pressTime = Date.now();
                        if (win.isConnected) {
                            drainAnim.stop();
                            fillAnim.start();
                        }
                    }
                    onReleased: {
                        const dt = Date.now() - pressTime;
                        fillAnim.stop();
                        drainAnim.start();
                        if (dt < 260 && win.radioOn && win.isConnected) {
                            win.showInfo = !win.showInfo;
                        }
                    }
                }
            }
        }

        // =====================================================================
        // ORBITING SATELLITE NODES (Rounded Frosted Pills)
        // =====================================================================
        Repeater {
            model: win.satellites

            Item {
                id: satItem
                required property var modelData
                required property int index

                readonly property var pos: win.satPos(index, win.satellites.length, modelData.ring)
                readonly property bool isHov: satMouse.containsMouse
                readonly property bool isBusy: win.connectingName === modelData.name

                // Staggered spring entrance out of the central core
                property real nodeGrow: win.wanted ? 1 : 0
                Behavior on nodeGrow {
                    SequentialAnimation {
                        PauseAnimation { duration: win.wanted ? 60 + satItem.index * 45 : 0 }
                        SpringAnimation { spring: 4.2; damping: 0.44; epsilon: 0.002 }
                    }
                }

                width: 174
                height: 54
                x: win.cx + (pos.x - win.cx) * nodeGrow - width / 2
                y: win.cy + (pos.y - win.cy) * nodeGrow - height / 2
                scale: Math.max(0.01, nodeGrow * (1 - 0.75 * Math.min(1, win.warp))) * (isHov ? 1.08 : 1.0)
                opacity: Math.min(1, nodeGrow * 1.4) * (1 - Math.min(1, win.warp)) * (1 - Math.min(1, win.swap))
                Behavior on scale { SpringAnimation { spring: 5.4; damping: 0.48 } }

                MultiEffect {
                    source: satPill
                    anchors.fill: satPill
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.45
                    shadowBlur: 0.8
                    shadowVerticalOffset: 4
                    z: -1
                }

                Rectangle {
                    id: satPill
                    anchors.fill: parent
                    radius: 27
                    color: satItem.isHov
                        ? win.activeColor
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.90)
                    border.width: satItem.isBusy || satItem.isHov ? 2.0 : 1.2
                    border.color: satItem.isBusy
                        ? Theme.fg
                        : (satItem.isHov ? Qt.lighter(win.activeColor, 1.2) : Qt.rgba(win.activeColor.r, win.activeColor.g, win.activeColor.b, 0.42))

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 17
                            color: satItem.isHov
                                ? Qt.rgba(0, 0, 0, 0.18)
                                : Qt.rgba(win.activeColor.r, win.activeColor.g, win.activeColor.b, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: satItem.modelData.icon || "󰤨"
                                color: satItem.isHov ? Theme.accentText : win.activeColor
                                font.family: Theme.font
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: satItem.modelData.name
                                color: satItem.isHov ? Theme.accentText : Theme.fg
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: satItem.isBusy ? "Connecting…" : (satItem.modelData.sub || "")
                                color: satItem.isHov
                                    ? Qt.rgba(Theme.accentText.r, Theme.accentText.g, Theme.accentText.b, 0.8)
                                    : Theme.fgDim
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                MouseArea {
                    id: satMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: win.hoveredSat = satItem.index
                    onExited: if (win.hoveredSat === satItem.index) win.hoveredSat = -1
                    onClicked: win.activateSatellite(satItem.modelData)
                }
            }
        }

        // =====================================================================
        // FLOATING BOTTOM CONTROL DOCK (Mode Pills + View Toggle + Radio Power)
        // =====================================================================
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 42 }
            width: dockRow.implicitWidth + 24
            height: 48
            radius: 24
            color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.88)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            // the active-tab pill: glides to the tab you pick (springs a little), in that tab's colour
            Rectangle {
                x: dockRow.x + win.tabTarget * 126
                Behavior on x { SpringAnimation { spring: 4.5; damping: 0.5; epsilon: 0.2 } }
                anchors.verticalCenter: parent.verticalCenter
                width: 118; height: 36; radius: 18
                color: win.tabTarget === 0 ? Theme.accent : Theme.accent2
                Behavior on color { ColorAnimation { duration: 260 } }
            }

            RowLayout {
                id: dockRow
                anchors.centerIn: parent
                spacing: 8

                // Wi-Fi / Bluetooth Tab Pills
                Repeater {
                    model: [
                        { idx: 0, label: "Wi-Fi",     icon: "󰤨" },
                        { idx: 1, label: "Bluetooth", icon: "󰂯" }
                    ]
                    Rectangle {
                        id: tabPill
                        required property var modelData
                        readonly property bool activeTab: win.tabTarget === modelData.idx
                        width: 118; height: 36
                        radius: 18
                        // the coloured pill is the glider below; the tab itself only lights on hover
                        color: (!activeTab && tabMouse.containsMouse) ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        z: 1
                        Behavior on color { ColorAnimation { duration: 180 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Text {
                                text: tabPill.modelData.icon
                                color: tabPill.activeTab ? Theme.accentText : Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 16
                            }
                            Text {
                                text: tabPill.modelData.label
                                color: tabPill.activeTab ? Theme.accentText : Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                        MouseArea {
                            id: tabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.requestTab(tabPill.modelData.idx)
                        }
                    }
                }

                Rectangle { width: 1; height: 22; color: Qt.rgba(1, 1, 1, 0.12) }

                // Telemetry vs Networks View Toggle Pill
                Rectangle {
                    width: 116; height: 36
                    radius: 18
                    color: viewMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: win.showInfo ? "󰍉" : "󰋼"
                            color: win.activeColor
                            font.family: Theme.font
                            font.pixelSize: 15
                        }
                        Text {
                            text: win.showInfo ? "Networks" : "Link Info"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                    MouseArea {
                        id: viewMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.showInfo = !win.showInfo
                    }
                }

                // Radio Power Toggle Pill
                Rectangle {
                    width: 84; height: 36
                    radius: 18
                    color: win.radioOn
                        ? Qt.rgba(win.activeColor.r, win.activeColor.g, win.activeColor.b, 0.22)
                        : Qt.rgba(1, 1, 1, 0.06)
                    border.color: win.radioOn ? win.activeColor : "transparent"
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "󰐥"
                            color: win.radioOn ? win.activeColor : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 14
                        }
                        Text {
                            text: win.radioOn ? "ON" : "OFF"
                            color: win.radioOn ? Theme.fg : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.radioOn = !win.radioOn;
                            if (win.tab === 0) Networking.wifiEnabled = win.radioOn;
                            else if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = win.radioOn;
                        }
                    }
                }
            }
        }
    }
}
