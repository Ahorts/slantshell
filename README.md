# slantshell

A quick demo desktop, put together with Claude Code at the Claude Builder Club. It's a small custom
shell for [Quickshell](https://quickshell.org) on Hyprland with slanted panels, a dynamic island, and a few
desktop widgets. It was built live: change something, look at a screenshot, give feedback, repeat.

> **This desktop is a demo.** It was made to look good in a three-minute video, not to survive your Tuesday.
> It has lightning on the borders, a bird living on a wire and a black hole that ends processes, so set your
> expectations accordingly. If you're feeling brave and want to daily drive it anyway, see
> [Daily driving it](#daily-driving-it-if-youre-feeling-brave) for the packages it quietly assumes you have.

## What's in it

- **Top bar** made of three slanted (parallelogram) panels:
  - left: launcher button and workspaces (scroll over them to change workspace)
  - centre, the **dynamic island**: shows the active window title. When music plays, a small
    **visualizer icon** sits next to the title. When the song changes, the island expands to show the
    full song name for a few seconds, then shrinks back. It also widens for **notifications** and pops
    up **volume / brightness** changes. Hover it while music plays for playback controls.
  - right: system tray, volume, battery, clock (click it for the dashboard)
- **App switcher & command centre** (`LauncherFace.qml`): a borderless center-screen floating overlay (no outer rectangular
  box) combining a RediWM-style 360° circular sector wheel on the left (central hub with a spring-driven directional
  pointer arrow, curved annular sectors that extrude outward when selected with a glowing outer arc rim and stacked
  multi-window depth arcs), a floating pill search bar at the top, and floating pill cards on the right. Supports prefix
  modes (`@` for open windows, `>` for system/shell actions) and an inline live math calculator (`Enter` copies the
  result to the clipboard)
- **Wi-Fi & Bluetooth orbital constellation** (`ConnectivityFace.qml`): a borderless center-screen floating overlay
  inspired by Anserin's `NetworkPopup.qml`. A gradient central core sphere pulses with a breathing halo, 3-ring
  expanding radar scan ripples, and a **Hold-to-Disconnect rippling fluid wave** (`disconnectFill`). Rounded satellite
  pills slowly orbit the core along two elliptical tracks (pausing smoothly on hover), linked by glowing tapered energy
  beams with travelling light packets. Quick-tap the core (or the bottom dock) to flip between live link telemetry
  satellites and available networks/devices; includes rich demo fallback nodes when no live APs/devices are in range.
  Click `󰤨` in the right bar pill or `ipc call connectivity toggle`
- **Wallpaper switcher**: its own full-screen window (`WallpaperWindow.qml`), not part of the island. A bright line
  shoots across the middle of the screen, opens like a shutter into a see-through band, and a film strip rolls in
  between two gear dials centred on the screen edges. The selected wallpaper is big in the middle; scrolling (or the
  arrow keys) turns both dials, runs the sprocket holes along and winds cards from one dial into the other on one
  spring. The strip creeps and the dials' hands and inner rings keep moving on their own. Enter applies, Esc closes.
- **Lightning borders** (`widgets/EdgeSpark.qml`): a border that is itself one continuous bolt (fine crackle all
  along, with brighter surges travelling round it), calm at rest and flaring on demand. On the island and the side
  bars (the island's surges with the bass while music plays), the notification countdown and volume gauge, highlighted
  items (corner-dial sector, app-switcher search row, the selected wallpaper card, today's date), the
  wallpaper dials, rails and band edges, the dashboard's dividers, record and graph card, and the focused Hyprland
  window's border (`WindowSparks.qml`). All bolts share one 25 Hz clock. TEMPORARY demo option:
  `ipc call lightning toggle|on|off|status` (`Theme.lightning`).
- **Dashboard** (`DashboardFace.qml`): an instrument cluster of three linked dials. Left: a gauge with three nested
  arcs (CPU, memory, disk) and a rolling CPU figure. Centre: the record (cover art spinning while it plays) inside a
  ring of audio bars, with the title, the current lyric line and the transport. Right: the month as a ring of day
  dots (past filled, today breathing) around the clock and date. Behind them: the cover art blurred into ambient
  light, soft glows drifting behind each dial and a faint dot grid. Opening: the record pops, the side dials slide out
  from behind it, the arcs sweep up and the days light up round the ring.
- **Lock screen** (`LockScreen.qml`, sample): a real session lock unlocked with your password (PAM). Big rolling
  clock in an energy core (a turning tick ring with the seconds sweeping round it), status pills (battery,
  network, music, user) on an orbit joined to the core by curved beams with light running along them, a beam down
  to the password pill that fires a spark into the core on every key (the charge ring fills as you type, it
  streams while checking, sparks recoil in red on a wrong password), and a password pill with a lightning edge where each
  typed dot pops in; Enter gathers the dots while it checks, a wrong password shakes them out in red; unlocking
  spirals the pills into the clock and clears the blur. The power menu's, corner dial's and switcher's Lock use it.
  `ipc call lock lock` (or `lock test`, which also unlocks
  itself after 2 minutes as a safety net).
- **App switcher: two scenes**: it opens on the window orbit: a large live preview of the selected window in the
  middle, your windows as pills (icon, app, workspace) on a ring around it, joined by thin beams. The ring turns so the
  selection comes round to the top (its pill lifts and lights, a pulse runs along its beam). Windows on hidden
  workspaces show a big app icon instead of a preview. The surface stays mapped (click-through) so it opens instantly. Typing (or Down, or the Apps/Actions
  chips) switches to search: the wheel spins, shrinks and arcs into the search bar's lens, the bar unrolls from it and
  the results cascade in. Esc, or Tab on an empty search, brings the wheel back out of the lens.
- **App switcher extras**: the wheel's hub shows a live picture of the selected window (screencopy), sectors name the
  app and its workspace, choosing a window focuses it through Hyprland (switching workspace if needed), the app list
  puts the apps you launch most at the top (`~/.local/state/slantshell/launches.json`), and one slanted highlight
  glides between rows.
- **Keeps the screen awake**: an idle inhibitor (like ii's) stops hypridle from dimming, locking or suspending while
  it is on (default on, remembered in `~/.local/state/slantshell/idle-inhibit`).
  It lists your whole skwd library (images, videos, Steam Workshop / Wallpaper Engine items), most recently used
  first. `ipc call wallpapers toggle|turn`
- **Dashboard drawer**: click the clock, or `ipc call dashboard toggle`. A face of the island with a mechanical
  vinyl turntable in the centre (circular-masked cover art, swinging tonearm, 32 radial audio-reactive spectrum bars,
  counter-rotating tick ring, click to flip to synced lyrics, slanted transport buttons), a slanted chrono-calendar
  wing on the left (live seconds sweep, month navigation with wheel/arrows), and a live telemetry wing on the right
  (auto-scaling CPU & RAM history sparklines with hover crosshair, CPU package temperature, uptime, and four rippling
  liquid orb gauges)
- **Desktop widgets**: a **shard clock** (`widgets/ShardClock.qml`: big slanted rolling digits on a slanted glass
  shard, a seconds line that steps forward with a glowing head, greeting and date; while music plays an equaliser
  grows out of the shard's top edge), a **weather shard** under it (`widgets/WeatherShard.qml`: drawn icon for the
  conditions that comes alive on refresh and hover, temperature, feels-like, high/low, place, humidity, wind, and a
  small forecast curve; data from wttr.in, which locates you by IP, refreshed every 20 minutes and cached), and
  **Flappy**, which lives on the desktop with no box: a little
  bird perched on a wire that comes in from the right edge. Click it and it hops off and flies left while slanted
  glass shards drift in from nowhere; crash and the shards fade away while the bird flies back to its wire (best
  score under the wire). Idle, it only blinks now and then; it can also play itself
- **Frosted glass**: the bar panels, island, dashboard and launcher show a blurred, screen-aligned copy of
  your wallpaper under a translucent tint (one small shader, `shaders/glass.frag`; rebuild with
  `/usr/lib/qt6/bin/qsb --qt6 glass.frag -o glass.frag.qsb`). `Theme.glass` turns it off.
- **Liquid gauges**: the dashboard's CPU / RAM / disk / battery are round glasses of rippling water that rise to
  the level
- **Banded diagonal wipe** (not used for wallpaper changes, which just fade the colours): three slanted
  palette-coloured bands sweep across the screen; the pet game uses it to cover the switch in and out.
  `ipc call wipe test` plays it; set `Theme.wipe` to use it on wallpaper switches
- **Synced lyrics**: while music plays, the island shows the line being sung (sliding up as it changes) and the
  dashboard's now-playing card shows the current and next lines. Lyrics come from [LRCLIB](https://lrclib.net)
  (an exact artist + title lookup, then a search), the lookup order skwd's daemon uses. When lyrics carry real
  word timing (Musixmatch richsync, or enhanced LRC) words light up as they are sung; otherwise the whole line is
  lit, and word timing is never estimated. Musixmatch is off by default (`musixmatch` in `Lyrics.qml`) because its
  anonymous endpoint currently gives out a null token and no richsync. Click the island to switch between the
  lyrics and the window name; the window name also flashes in briefly whenever the focused window changes. Only
  the artist, title and length of the playing track are sent, nothing is stored.
  `ipc call lyrics info` shows where the current lyrics came from.
- **System galaxy**: the machine as a little universe. It warps in from the stars to a black hole with an
  accretion disk, four planets orbiting it as dials (CPU, memory, disk, temperature), and your busiest programs as
  glassy bubbles (size = memory, colour = CPU; an app with many processes is one bubble). The bubbles have real
  physics: they swirl around the hole and bump into each other and the walls. Drag one to carry it and let go to
  throw it, wheel to zoom, click one for its details and recent CPU on the left. To end a program, throw it into the
  black hole: it asks "End it?", Enter sends a polite quit request (SIGTERM, never SIGKILL), Esc sets it free.
  Session essentials (the compositor, this shell, audio, shells) are protected. `ipc call galaxy toggle`, from the
  corner dial, or `galaxy select|end <name>` / `confirm` / `cancel` without a mouse
- **Desktop pet**: a small cat that lives on the desktop (windows cover it) wanders along the bottom, sits, blinks
  and hops to the bass of the music. Click it and the banded wipe sweeps the screen; underneath, it becomes the
  runner of a dino-style game on a strip along the bottom: click or Space/Up to jump the shards, Esc to quit, and on
  a crash another wipe takes you back to the pet. `ipc call pet on|off`,
  `pet game on|off`, `pet auto on|off` (a bot plays)
- **Corner dial**: rest the pointer in the bottom-left corner and a quarter dial of quick actions swings out
  (sectors with a gliding indicator, a drifting tick ring that jumps when you scroll to the next set, a core with
  the time) (wallpapers, dashboard, apps, lock, power; scroll for a second set: Wi-Fi & Bluetooth, hard edges,
  Flappy autopilot, galaxy, pet). `ipc call wheel open|close|turn`
- **Power menu**: dead centre, four big slanted bars in a diagonal cascade (lock, log out, restart, shut down).
  Up/Down or hover, Enter to run; log out, restart and shut down ask once more. `ipc call power toggle`
- **Spring motion**: the island and its faces are driven by springs instead of eased curves. Width pulls hard
  and arrives first, height is slacker and overshoots a little, so a drawer widens and then drops; a spring keeps
  its velocity when the target changes, so nothing restarts. Content leaves in half the time it takes to arrive,
  slides in from the side, and panels grow from 90% scale. Opening one drawer sends the others back into the island.
  (The approach is borrowed from the ideas in [pocket-dots](https://github.com/diegoMalagrida/pocket-dots); no code
  was copied, it is GPL-3.0.)
- **One island, many faces**: the dashboard, launcher and Wi-Fi & Bluetooth panel are not separate windows or popups.
  The island is the one shape of the top surface (a single full-screen layer that only takes input where there is
  something to click), and it reshapes itself into whichever face you ask for: width on a tight spring, height on a
  looser one that overshoots a little, then the face's content fades in once the shape has arrived. Switching
  straight from one face to another reshapes the same shape. `BarZone.qml` reserves the bar's strip.
- **Wi-Fi & Bluetooth**: a face of the island, drawn as a constellation. The hub is what you are connected to; its
  details (signal, security, address, frequency, Scan) sit around it as chips on thin lines, other networks or
  paired devices further out. Click one to connect (its line turns into marching dashes meanwhile). Tabs at the
  bottom, the radio's power switch bottom right. `ipc call connectivity toggle`
- **Gooey split island**: when music is playing and a notification or volume popup arrives, a small music chip
  separates from the island so the song stays visible, then merges back
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
qs -p /path/to/slantshell ipc call idle toggle         # keep the screen awake on/off (also: on, off, status)
```

## Daily driving it (if you're feeling brave)

Bold choice. Respect. Here's what it leans on. Most of it is probably already on your machine if you run
Hyprland; the rest you'll find out about the fun way (a blank space where a widget should be).

**The essentials** (no these, no desktop):
- **Hyprland 0.57+** with the **Lua config**. Every dispatch is written as `hl.dsp.…`; older hyprlang
  configs will just stare back at you.
- **Quickshell 0.3+** (tested on 0.3.2). Run it with `qs -p`, it's not a package you install into it.
- **A Nerd Font** (e.g. Symbols Nerd Font). Without one every icon becomes a polite little box.
- **PipeWire + WirePlumber** (volume), **UPower** (battery), **NetworkManager** (Wi-Fi and `nmcli`), **BlueZ**
  (Bluetooth), **PAM** (the lock screen: yes, it uses your real password, no, it doesn't send it anywhere).
- A **StatusNotifier tray host** for the tray icons, and **no other notification daemon** running (mako, dunst
  and friends have to sit this one out).

**The fun parts** (each one quietly disappears without its package):
- [**cava**](https://github.com/karlstav/cava): the island visualizer and the equaliser on the clock shard.
  It runs only while music plays.
- **curl**: synced lyrics from [LRCLIB](https://lrclib.net) and the weather from [wttr.in](https://wttr.in)
  (which guesses your city from your IP, like a very polite stalker).
- [**skwd-wall**](https://github.com/liixini/skwd-wall) (`skwd-helm`): the wallpaper switcher, including video and Wallpaper
  Engine scenes. Without it the switcher falls back to the images in `~/Pictures/Wallpapers`.
- [**matugen**](https://github.com/InioX/matugen): recolours the shell and your window borders from the
  wallpaper. Optional: an [illogical-impulse](https://github.com/end-4/dots-hyprland) setup, so terminals,
  GTK and Qt get recoloured too (its `switchwall.sh` is picked up automatically).
- **kitty**: terminal apps (Neovim, btop, ...) opened from the switcher's search run in it.
- **wl-clipboard**: the switcher's calculator copies its result with `wl-copy`.
- **procps / coreutils** (`ps`, `df`): the system galaxy and the dashboard gauges. You have these. Probably.
- A **backlight device** for the brightness popups. The name is `backlight` in `Island.qml` (default
  `intel_backlight`; see `/sys/class/backlight/`). Desktop PC? The brightness popup simply never comes. Peace.

**Things it will do to your session** (you were warned, kind of):
- Squares your window corners on start ("hard edges"); `ipc call sharp off` gives the curves back.
- Keeps the screen awake by default (`ipc call idle off` lets it sleep again).
- Puts lightning on your focused window's border. `ipc call lightning windowsOff` if your eyes need a break,
  `ipc call lightning off` to ground the whole thing.
- The black hole in the system galaxy really ends programs (gently, with SIGTERM, after asking). The shell,
  Hyprland and your session are protected. Your unsaved work in other apps is not. Choose your victims wisely.

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
| `Lyrics.qml` | synced lyrics (LRCLIB lookup, parsing, follows the playback position) |
| `WallpaperPicker.qml` | wallpaper switcher (uses `skwd-helm` and a `matugen` dry run) |
| `SkewPanel.qml` | the parallelogram shape |
| `Launcher.qml` | app switcher / launcher |
| `Notifs.qml` | notification daemon and queue |
| `Theme.qml` | colours and wallpaper path, watches the palette files |
| `Background.qml` | desktop widgets layer (transparent, above the wallpaper) |
| `DashboardFace.qml`, `LauncherFace.qml`, `ConnectivityFace.qml` | faces the island reshapes itself into |
| `PowerMenu.qml` | dead-centre diagonal cascade power menu |
| `BarZone.qml` | reserves the bar strip (the island window covers the screen) |
| `Galaxy.qml` | the system galaxy (process monitor) |
| `Pet.qml` | the desktop pet and its game |
| `widgets/` | pulse clock, calendar, now playing, system gauges, Flappy Bird |

## Notes

- The bar window never resizes; only the panels inside it animate, which keeps motion smooth.
- The widgets layer sits above the wallpaper renderer and draws no wallpaper of its own.
