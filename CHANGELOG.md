# Changelog

All notable changes to Notch are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [1.3.0] - 2026-09-30

- Add a setting to show the notch on every connected display.


## [1.2.0] - 2026-09-28

- On MacBooks with a camera notch, show collapsed content beside the camera so it is visible.
- Switch between Now Playing, coding agents, the next meeting, and the shelf in the expanded notch.
- Show a timer while a coding agent works, reply to agent questions in iTerm2 or Terminal, and allow or deny permission prompts from the notch.
- Count down to the end of a Claude rate limit and say when it lifts.
- Add a `notch` command: `notch done`, `notch fail`, `notch ask`, and `notch run`.
- Count down to the next calendar event with a Join button for video calls.
- Announce the microphone or camera turning on, headphones connecting with their battery level, and volume and brightness changes.
- Hold files dragged onto the notch on a shelf; drag them out or AirDrop them.
- Distinct trackpad taps for requests, finished tasks, and failures, and a setting to turn off hover taps.
- Show Claude Code, Cursor, and Codex in the notch when they need permission, ask a question, finish, or fail, with sounds and a list of recent sessions in the expanded notch. Install the hooks from Settings → Coding Agents.
- Click a coding-agent session to jump to its iTerm2 or Terminal tab, or to the editor window for its project.
- Show "Nothing playing" instead of an empty expanded notch.
- Put the reply field where the detail line goes, and ask for Automation even when the target app is closed.
- Always show the result of a `notch` command.
- Scroll through all coding-agent sessions in the expanded notch.
- Add a landing page at djui.github.io/notch.


## [1.1.3] - 2026-09-24

- Play hover haptics even when Notch is not the frontmost app.


## [1.1.2] - 2026-09-24

- Give haptic feedback when hovering into and out of the notch.


## [1.1.1] - 2026-09-23

- Keep Now Playing text inside the notch and marquee long titles.


## [1.1.0] - 2026-09-23

- Restack Now Playing into an iOS-style player that stays inside the notch.
- Move clipboard history out of Notch and drop the open shortcut.


## [1.0.1] - 2026-09-15

### Fixed

- Opening the clipboard from the hotkey highlights the first/latest clip so Return pastes the most recent copy


## [1.0] - 2026-09-15

### Added

- Now Playing in the collapsed and expanded notch
- About dialog with version, build, and homepage
- Relaunch command in the app menu
- Notch-shaped Dock and menu bar icon that follows light and dark mode
- Live checkmark when Accessibility paste access is granted
- Hide the notch in fullscreen, Mission Control, games, and screen capture
- Charging, Low Power, and Focus events in the collapsed notch
- iOS-style equalizer while media is playing
- First-launch permission onboarding and a Permissions settings pane
- Optional setting to keep the notch visible in fullscreen, Mission Control, games, and screenshots (off by default)
- Switch between Notch and Dynamic Island layouts in Settings, the overlay menu, and the menu bar
- Clear clipboard history while keeping pinned clips
- Full Disk Access status on the Permissions pane for Focus mode identity
- Optional setting to disable clipboard history (enabled by default)
- Click the expanded Now Playing title to open the source app, window, or browser tab

### Changed

- Rounder collapsed and expanded notch corners
- Collapsed notch sits slightly shorter than the menu bar, like a hardware notch
- Clipboard selection ring is drawn inside the card so it is no longer clipped
- Debug builds no longer use Xcode’s debug dylib, which made Accessibility and paste fail even after permission was granted

### Fixed

- Collapse the notch when opening Settings so it does not stay expanded behind the dialog
- Release build of the MediaRemote helper
- Center the About dialog on the notch display each time it opens
- Sendable, mutability, and AppIcon asset warnings
- Accessibility and Automation permission status in Settings
- Paste into the previous app (notch was keeping keyboard focus and skipping ⌘V)
- Opening Settings no longer expands the notch again via a reopen event
- Equalizer hides while media is paused
- Focus on/off events in the collapsed notch (the assertion store is not readable without Full Disk Access)
- Focus live activity shows the active mode’s name and symbol, including switches between modes
- Clicking a clipboard card pastes it (⌘1 already did)
- Expand and collapse stay anchored to the top center
- Reopen a hidden or windowless player when clicking the Now Playing title

[Unreleased]: https://github.com/djui/notch/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/djui/notch/releases/tag/v1.3.0
[1.2.0]: https://github.com/djui/notch/releases/tag/v1.2.0
[1.1.3]: https://github.com/djui/notch/releases/tag/v1.1.3
[1.1.2]: https://github.com/djui/notch/releases/tag/v1.1.2
[1.1.1]: https://github.com/djui/notch/releases/tag/v1.1.1
[1.1.0]: https://github.com/djui/notch/releases/tag/v1.1.0
[1.0.1]: https://github.com/djui/notch/releases/tag/v1.0.1
[1.0]: https://github.com/djui/notch/releases/tag/v1.0
