# Changelog

All notable changes to Notch are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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

[Unreleased]: https://github.com/djui/Notch/compare/v1.0...HEAD
[1.0]: https://github.com/djui/Notch/releases/tag/v1.0
