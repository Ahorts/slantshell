# slantshell

A quick demo desktop, put together with Claude Code at the Claude Builder Club. It's a small custom
shell for [Quickshell](https://quickshell.org) on Hyprland with slanted panels, a dynamic island, and a few
desktop widgets. It was built live: change something, look at a screenshot, give feedback, repeat.

> **This desktop is a demo.** It was made to look good in a three-minute video, not to survive your Tuesday.
> It has lightning on the borders, a bird living on a wire and a black hole that ends processes, so set your
> expectations accordingly. If you're feeling brave and want to daily drive it anyway, see
> [Daily driving it](#daily-driving-it-if-youre-feeling-brave) for the packages it quietly assumes you have.

## Demo video

They say a picture is worth a thousand words. This is three minutes at 60 fps, so that's 10,800 pictures,
which makes it roughly 10.8 million words. Duh. You were never going to read all of that anyway.

https://github.com/user-attachments/assets/8c042ba7-acea-4931-8260-8ce87d44be83

## What's in it

- A slanted top bar with a **dynamic island**: window titles, synced lyrics, notifications, volume and brightness
- **Lightning borders** on the bars, the island and your focused window
- A **window switcher** that orbits your windows around a live preview, with app search
- A **dashboard**, a **Wi-Fi & Bluetooth** panel and a **wallpaper switcher** that recolours everything
- A **lock screen**, a **power menu** and a **corner dial** of quick actions
- A **system galaxy**: your programs as bubbles; throw one into the black hole to end it
- Desktop widgets: a clock, the weather, **Flappy** on a wire and a pet that turns into a runner game

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
- [**skwd-wall**](https://github.com/liixini/skwd-wall) (`skwd-helm`): the wallpaper switcher, including video and
  Wallpaper Engine scenes. Without it the switcher falls back to the images in `~/Pictures/Wallpapers`.
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
- **Battery life?** Never heard of her. All that lightning is redrawn many times a second, so on a laptop
  unplugged, `qs -p /path/to/slantshell ipc call lightning off` buys you some of it back (the bars, island,
  windows and dials go back to plain, calm borders). `ipc call lightning on` when you're plugged in and feeling
  dramatic again.
- The black hole in the system galaxy really ends programs (gently, with SIGTERM, after asking). The shell,
  Hyprland and your session are protected. Your unsaved work in other apps is not. Choose your victims wisely.

## Run

Clone the repo, then:

```sh
qs -p /path/to/slantshell
```

Bind the window switcher to a key in your Hyprland (Lua) config:

```lua
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs -p /path/to/slantshell ipc call launcher toggle"))
```

Everything else is reachable from the bar or the corner dial (rest the pointer in the bottom-left corner).
