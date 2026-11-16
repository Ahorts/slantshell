import Quickshell
import Quickshell.Io
import QtQuick

// slantshell: a quick demo Quickshell desktop. Run with:  qs -p /path/to/slantshell
//
// Launcher / app switcher IPC (bind these to a key in your Hyprland config):
//   qs -p /path/to/slantshell ipc call launcher toggle
ShellRoot {
    id: root

    property bool launcherOpen: false

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Background { screen: perScreen.modelData }
            Island {
                screen: perScreen.modelData
                onLauncherClicked: root.launcherOpen = !root.launcherOpen
            }
            Launcher {
                screen: perScreen.modelData
                open: root.launcherOpen
                onCloseRequested: root.launcherOpen = false
            }
        }
    }
}
