# Notch

A macOS overlay that sits on the built-in display notch and expands into a Dynamic Island–style tray.

It shows Now Playing and live activities for charging, Low Power Mode, and Focus. Clipboard history lives in [Clip](https://github.com/djui/Clip).

Requires **macOS 15** or later.

## Install

1. Download `Notch-1.0.zip` from the [latest release](https://github.com/djui/Notch/releases/latest).
2. Unzip and move `Notch.app` to `/Applications`.
3. Open the app.

The release is signed with an Apple Development certificate, not notarized. If macOS refuses to open it:

```bash
xattr -cr /Applications/Notch.app
```

Then open the app normally. First launch walks through permissions and enables launch at login.

## Features

- **Layouts.** Switch between Notch and Dynamic Island from Settings, the overlay, or the menu bar.
- **Now Playing.** Title, artist, artwork, and playback controls in the collapsed and expanded notch. Click the expanded title to open the source app, window, or browser tab.
- **Live activities.** Charging, Low Power Mode, and Focus appear in the collapsed notch. Each can be turned off in Settings.
- **Open.** Hover or click the notch. Hover can be turned off in Settings.
- **Hides by default** in fullscreen, Mission Control, games, and screen capture. That can be overridden in Settings.

## Permissions

| Permission | Used for |
| --- | --- |
| Accessibility | Bring the playing app forward |
| Automation (Music, Spotify, Safari, Chrome) | Now Playing artwork, controls, and browser tabs with audio |
| Full Disk Access | Focus mode name and icon |

macOS treats the Xcode debug build and a released `Notch.app` as different binaries. Enable the Accessibility entry that matches the copy you are running, then relaunch.

## Build

Open `Notch.xcodeproj` in Xcode 16 or later, or:

```bash
./scripts/release.sh --build-only
open dist/Notch.app
```

Cut a GitHub release from `main`:

```bash
./scripts/release.sh --patch
```

## License

[MIT](LICENSE)
