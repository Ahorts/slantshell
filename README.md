# slantshell

A quick demo desktop, put together with Claude Code at the Claude Builder Club. It's a small custom
shell for [Quickshell](https://quickshell.org) on Hyprland with slanted panels, a dynamic island, and a few
desktop widgets. It was built live: change something, look at a screenshot, give feedback, repeat.

## What's in it

- **Top bar** made of three slanted (parallelogram) panels:
  - left: launcher button and workspaces (scroll over them to change workspace)
  - centre, the **dynamic island**: shows the active window title. When music plays, a small
    **visualizer icon** sits next to the title. When the song changes, the island expands to show the
    full song name for a few seconds, then shrinks back. It also widens for **notifications** and pops
    up **volume / brightness** changes. Hover it while music plays for playback controls.
  - right: system tray, volume, battery, clock (click it for the dashboard)
- **App switcher / launcher** overlay: open windows plus installed apps, type to filter
- **Wallpaper switcher**: a minimal carousel of slanted cards (arrows or scroll to browse, Enter to apply,
  Esc to close). Pick one and the shell *and Hyprland's window borders* recolour to it. The border
  colours are set live; a Hyprland config reload restores whatever `colors.lua` says
- **Dashboard drawer** (Caelestia-style): click the clock, or `ipc call dashboard toggle`. It slides down
  from the bar with a calendar, a now-playing card (cover art, title, live visualizer, controls) and live
  CPU / RAM / disk / battery gauges. It closes itself when the pointer leaves
- **Desktop widgets**: a **pulse clock** (a clock inside a ring with a seconds sweep that grows live
  audio-reactive bars from cava while music plays) and a playable **Flappy Bird** that can also play itself
- **Frosted glass**: the bar panels, island, dashboard and launcher show a blurred, screen-aligned copy of
  your wallpaper under a translucent tint (one small shader, `shaders/glass.frag`; rebuild with
  `/usr/lib/qt6/bin/qsb --qt6 glass.frag -o glass.frag.qsb`). `Theme.glass` turns it off.
- **Liquid gauges**: the dashboard's CPU / RAM / disk / battery are round glasses of rippling water that rise to
  the level
- **Banded diagonal wipe**: a wallpaper switch sweeps three slanted palette-coloured bands across the screen and
  recolours the shell underneath them (`ipc call wipe test` plays it once)
- **Ambient spectrum**: translucent audio bars along the bottom of the desktop while music plays
- **Wallpaper-aware colours**: the theme follows your matugen palette and the wallpaper switcher
- Acts as the notification daemon (`org.freedesktop.Notifications`)

### The outline is the UI

The island's slanted outline doubles as a gauge. It **drains as a countdown** while a notification is
shown (paused while you hover it), and it **fills like a meter** for volume and brightness changes.
Nothing extra is drawn: the border you already see turns into the indicator.

### Hard edges (default)

Hyprland can't slant real windows, so the slant lives in the shell. To match it, the shell squares your
window corners on startup and keeps your own border (which already follows the palette). Switch it off
live, or change the default (`sharp` in `shell.qml`):

```sh
qs -p /path/to/slantshell ipc call sharp toggle   # turning it off reloads your Hyprland config
```

If you quit the shell, your rounding stays square until Hyprland's next config reload (`hyprctl reload`).

### Theming other apps (optional)

On a wallpaper switch the shell always recolours itself and Hyprland's window borders, which only needs
`matugen`. To theme other apps too (terminal, GTK, Qt, ...) it can run a command in the background:
if an [illogical-impulse](https://github.com/end-4/dots-hyprland) setup is found, it runs that setup's
`~/.config/quickshell/ii/scripts/colors/switchwall.sh --image <wallpaper> --noswitch`. If that script
isn't there (or fails) it falls back to the matugen-only recolour. To use your own pipeline, change
`themeScript` / `generateFrom` in `Theme.qml`.

### Other IPC

```sh
qs -p /path/to/slantshell ipc call dashboard toggle    # dashboard drawer
qs -p /path/to/slantshell ipc call wallpapers toggle   # wallpaper switcher
qs -p /path/to/slantshell ipc call flappy on           # let Flappy Bird play itself (off to stop)
```

## Requirements

- Quickshell 0.3+ (tested on 0.3.2)
- Hyprland (workspace and window info come from it)
- PipeWire, UPower, and a StatusNotifier tray host for the matching bar items
- [cava](https://github.com/karlstav/cava) for the island visualizer (it uses its own raw config, `cava.conf`)
- A backlight device for brightness popups. The device name is `backlight` in `Island.qml`
  (default `intel_backlight`; see `/sys/class/backlight/`)
- Optional: skwd wallpaper tools (`skwd-helm`) for the wallpaper switcher
- Optional: [matugen](https://github.com/InioX/matugen) writing a Material You palette to
  `~/.local/state/quickshell/user/generated/colors.json`, and a wallpaper path in
  `~/.local/state/quickshell/user/generated/wallpaper/path.txt`. Without them the built-in default
  colours are used.

## Run

Clone the repo, then:

```sh
qs -p /path/to/slantshell
```

Only one notification daemon can run at a time, so stop other ones (mako, dunst, another shell) first.

### Toggle the launcher

```sh
qs -p /path/to/slantshell ipc call launcher toggle
```

Example Hyprland (Lua config) bind:

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs -p /path/to/slantshell ipc call launcher toggle"))
```

Workspace clicks use `hyprctl dispatch 'hl.dsp.focus({ workspace = N })'`, the Lua-config dispatch syntax.
On older Hyprland versions you may need to change `gotoWorkspace` in `Island.qml`.

## Layout

| File | Purpose |
|---|---|
| `shell.qml` | entry point, creates the pieces per screen, launcher IPC |
| `Island.qml` | the top bar and dynamic island |
| `Audio.qml` | shared player state and live cava levels |
| `WallpaperPicker.qml` | wallpaper switcher (uses `skwd-helm` and a `matugen` dry run) |
| `SkewPanel.qml` | the parallelogram shape |
| `Launcher.qml` | app switcher / launcher |
| `Notifs.qml` | notification daemon and queue |
| `Theme.qml` | colours and wallpaper path, watches the palette files |
| `Background.qml` | desktop widgets layer (transparent, above the wallpaper) |
| `Dashboard.qml` | the drop-down dashboard drawer |
| `widgets/` | pulse clock, calendar, now playing, system gauges, Flappy Bird |

## Notes

- The bar window never resizes; only the panels inside it animate, which keeps motion smooth.
- The widgets layer sits above the wallpaper renderer and draws no wallpaper of its own.
