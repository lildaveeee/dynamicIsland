# Dynamic island

A dynamic island shell for Hyprland, built with [Quickshell](https://quickshell.outfoxxed.me/).

## Features

- **Dynamic island** — click, right-click, middle-click, or drag to switch between panels. All actions are configurable.
- **Music panel** — shows current track, artist, album art, and playback controls via MPD. Live audio visualiser powered by cava.
- **Notifications** — integrates with dunst, displays incoming notifications with app icon and a dismiss timer. Supports clicking through to the app or URL.
- **Notification history** — scrollable log of past notifications, persisted across sessions.
- **App launcher** — fuzzy search with favourites pinning. Favourites are saved to disk.
- **Control panel** — volume, per-app volume, brightness, Wi-Fi toggle and network list, Bluetooth toggle, VPN, OBS recording indicator, and a silence toggle.
- **Screen time** — tracks active window focus time per app, including Steam games. Shows session and total time, with app icons pulled from .desktop entries or Steam's library cache.
- **Color picker** — hue ring + saturation/value square to customize pill color, accent color, and text color.
- **Per-monitor scaling** — UI scales automatically based on the focused monitor's resolution.
- **Global shortcut** — toggle island visibility from anywhere.

## Dependencies

- [Quickshell](https://quickshell.outfoxxed.me/) (with Wayland and Hyprland modules)
- Hyprland
- dunst
- MPD + mpc
- cava
- NetworkManager / connman (for Wi-Fi)
- PipeWire / PulseAudio (for per-app volume)
- `ffmpeg` (for album art extraction)
- `brightnessctl` or equivalent (for brightness control)
- OBS (optional, for recording status)

## Installation

1. Clone the repository into your Quickshell config directory:

```
git clone https://github.com/lildaveeee/island ~/.config/quickshell/island
```

2. Make sure all the scripts in `scripts/` are executable:

```
chmod +x ~/.config/quickshell/island/scripts/*.sh
```

3. Run with Quickshell:

```
quickshell -p ~/.config/quickshell/island
```

Or add it to your Hyprland config to launch on startup:

```
exec-once = quickshell -p ~/.config/quickshell/island
```

## Configuration

At the top of `shell.qml`, you can change which panel opens on each interaction:

```qml
property string clickLeft:   "music"
property string clickRight:  "controlPanel"
property string clickMiddle: "notifHistory"
property string dragDown:      "appLauncher"
property string dragDownRight: "screenTime"
```

Valid values: `music`, `controlPanel`, `notifHistory`, `appLauncher`, `screenTime`, `notification`, `none`.

Colors (pill, accent, text) can be changed at runtime from within the control panel color picker, or by editing the defaults directly in `shell.qml`.

## Notes

- Screentime and notification history are saved to `~/.config/quickshell/island/` between sessions.
- The island is designed for a 1080p baseline and scales up or down based on the focused monitor.
- Steam game tracking resolves app IDs to names using local manifest files — no network requests.
