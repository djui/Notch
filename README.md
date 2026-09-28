# Notch

A macOS overlay that sits on the built-in display notch and expands into a Dynamic Island–style tray.

It shows Now Playing, live activities for charging, Low Power Mode, and Focus, and tells you when Claude Code, Cursor, or Codex needs you. Clipboard history lives in [Clip](https://github.com/djui/Clip).

Requires **macOS 15** or later. Website: [djui.github.io/Notch](https://djui.github.io/Notch/).

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
- **Coding agents.** Claude Code, Cursor, and Codex appear in the notch when they need permission, ask a question, finish, or fail, with a running timer while they work. The expanded notch lists recent sessions; click one to jump to its terminal tab or editor window, reply to a question in iTerm2 or Terminal, or allow and deny permission prompts.
- **More live activities.** Microphone and camera turning on, headphones connecting with battery, volume and brightness, and a countdown to your next meeting with a Join button. Meetings and volume are off by default.
- **Shelf.** Drag files onto the notch to keep them at hand, drag them out again, or AirDrop them.
- **Notches with a camera.** On MacBooks with a camera housing, collapsed content sits to the left and right of it, like the iPhone's Dynamic Island.
- **Open.** Hover or click the notch. Hover can be turned off in Settings.
- **Hides by default** in fullscreen, Mission Control, games, and screen capture. That can be overridden in Settings.

## Permissions

| Permission | Used for |
| --- | --- |
| Accessibility | Bring the playing app forward |
| Automation (Music, Spotify, Safari, Chrome) | Now Playing artwork, controls, and browser tabs with audio |
| Full Disk Access | Focus mode name and icon |
| Automation (iTerm2, Terminal) | Jump to the tab a coding agent runs in, and type replies into it |
| Calendars | Next-meeting countdown (only when turned on) |

macOS treats the Xcode debug build and a released `Notch.app` as different binaries. Enable the Accessibility entry that matches the copy you are running, then relaunch.

## Coding agents

Open Settings → Coding Agents and click Install next to each agent. Notch writes a small script to `~/.config/notch/notch-hook` and registers it as a hook:

| Agent | Config | Events |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | Permission prompts, questions, idle input, finished, failed, session lifecycle |
| Codex | `~/.codex/hooks.json` | Approval requests, questions, finished, session lifecycle |
| Cursor | `~/.cursor/hooks.json` | Finished, failed, session lifecycle |

Existing hooks stay as they are, and the previous file is kept as `<name>.notch-backup`. Codex runs a new hook only after you trust it: start Codex and run `/hooks`. Cursor has no hook for approval prompts.

With “Allow or deny permission prompts from the notch” on, the permission hook waits up to 25 seconds for your answer while the agent's app is in the background, then lets the agent ask as usual. Hooks installed by an earlier version show Repair in Settings.

Run `notch done "Tests passed"`, `notch fail`, `notch ask`, or `notch run make test` from any shell once Settings installs the `notch` command (linked into `~/.local/bin` when that folder exists).

The script passes each event to Notch over a Unix socket that only your user can open, so events never leave your Mac. It always exits 0 without output, so it cannot block or change what an agent does. To forward events from another tool, pipe a Claude Code–style hook payload into `~/.config/notch/notch-hook claude`.

## Build

To work on the camera-housing layout on a Mac without one:

```bash
defaults write com.djui.notch simulateHardwareNotch -bool YES
```

Open `Notch.xcodeproj` in Xcode 16 or later, or:

```bash
./scripts/release.sh --build-only
open dist/Notch.app
```

Cut a GitHub release from `main`:

```bash
./scripts/release.sh --patch
```

## Website

The landing page lives in `site/` and deploys to GitHub Pages on every push to `main` that touches it. Preview it locally:

```bash
python3 -m http.server -d site
```

## License

[MIT](LICENSE)
