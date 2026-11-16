# qs-desktop

A small custom desktop shell for [Quickshell](https://quickshell.org) on Hyprland, built with Claude Code
for a Claude Builder Club session. It was iterated live: change something, look at a screenshot, give
feedback, repeat.

## What's in it

- **Top bar** made of three slanted (parallelogram) panels:
  - left: launcher button and workspaces
  - centre, the **dynamic island**: shows the active window title, switches to the track when media is
    playing (with controls on hover), and widens to show **notifications**
  - right: system tray, volume, battery, clock
- **App switcher / launcher** overlay: open windows plus installed apps, type to filter
- **Desktop widgets**: clock with greeting, month calendar, CPU / RAM / disk / battery rings, and a
  playable **Flappy Bird**
- **Wallpaper-aware colours**: the theme follows your matugen palette and updates live
- Acts as the notification daemon (`org.freedesktop.Notifications`)

## Requirements

- Quickshell 0.3+ (tested on 0.3.2)
- Hyprland (workspace and window info come from it)
- PipeWire, UPower, and a StatusNotifier tray host for the matching bar items
- Optional: [matugen](https://github.com/InioX/matugen) writing a Material You palette to
  `~/.local/state/quickshell/user/generated/colors.json`, and a wallpaper path in
  `~/.local/state/quickshell/user/generated/wallpaper/path.txt`. Without them the built-in default
  colours are used.

## Run

```sh
qs -p /path/to/qs-desktop
```

Only one notification daemon can run at a time, so stop other ones (mako, dunst, another shell) first.

### Toggle the launcher

```sh
qs -p /path/to/qs-desktop ipc call launcher toggle
```

Example Hyprland (Lua config) bind:

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs -p /path/to/qs-desktop ipc call launcher toggle"))
```

Workspace clicks use `hyprctl dispatch 'hl.dsp.focus({ workspace = N })'`, the Lua-config dispatch syntax.
On older Hyprland versions you may need to change `gotoWorkspace` in `Island.qml`.

## Layout

| File | Purpose |
|---|---|
| `shell.qml` | entry point, creates the pieces per screen, launcher IPC |
| `Island.qml` | the top bar and dynamic island |
| `SkewPanel.qml` | the parallelogram shape |
| `Launcher.qml` | app switcher / launcher |
| `Notifs.qml` | notification daemon and queue |
| `Theme.qml` | colours and wallpaper path, watches the palette files |
| `Background.qml` | desktop widgets layer (transparent, above the wallpaper) |
| `widgets/` | clock, calendar, system rings, Flappy Bird |

## Notes

- The bar window never resizes; only the panels inside it animate, which keeps motion smooth.
- The widgets layer sits above the wallpaper renderer and draws no wallpaper of its own.
