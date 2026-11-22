# Changelog

All notable changes to DialPilot are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions use
[Semantic Versioning](https://semver.org/).

中文版：[CHANGELOG.zh.md](CHANGELOG.zh.md)

## [1.1.1] — 2026-11-22

Distribution release: DialPilot now ships as a downloadable disk image, so
using it no longer requires a toolchain.

### Added

- **DMG installer** (`scripts/make-dmg.sh`) — builds `DialPilot.app` and packs
  it with an `/Applications` shortcut into a signed, zlib-compressed image at
  `dist/DialPilot-<version>.dmg`. Every release attaches this file.

### Changed

- Install docs now lead with the download path; building from source is the
  fallback for people who want to read or patch the code.
- The notes explain the one Gatekeeper step: the app is signed with an Apple
  Development certificate and is **not notarized**, so the first launch needs
  right-click → Open (or System Settings → Privacy & Security → Open Anyway).

### Removed

- Share-kit drafts (`docs/share.md`, `docs/share.zh.md`) — release notes live
  here and on the GitHub Releases page instead.

## [1.1.0] — 2026-11-21

The "make it disappear into the menu bar" release: the panel owns its own
window, the device state stops lying, and the whole UI is bilingual.

### Added

- **Menu-bar status badge** with a fixed priority: device absent/powered off →
  permission missing → low battery → charging → normal. Healthy setups show
  no badge at all (`DialStatusBar`).
- **Battery ring gauge** and an iStat-style usage card: today / lifetime
  counts, most-used control, 7-day bar chart with per-bar values and a hover
  detail row (`PanelGauges`).
- **Local usage statistics** (`usage.json`, 90-day retention, lifetime
  totals, no network or identifiers).
- **Full-screen light guide** (Raycast-style): one card per agent state,
  ←/→ or horizontal swipe to page, click or Esc to close.
- **Device liveness detection**: a powered-off AU05 stays on USB and ACKs
  heartbeats; two unanswered power queries now surface as
  *Connected · not responding* with the stale battery cleared
  (`DialDeviceLiveness`).
- **Permission banner** with one-click jumps to the exact System Settings
  panes.
- **Bilingual UI** (English / 简体中文) through a typed key table, following
  the system language.
- **App icon** (`AppIcon.icns`).
- 21 new tests over the previous suite; **271 total** (Core 247 + App 24),
  covering panel geometry, status badge, liveness, usage stats,
  localization, panel layout and opt-in snapshots.

### Changed

- The panel is now a borderless `NSPanel` owned by `DialPanelController`
  instead of an `NSPopover`. Window size is exactly `content + arrow`,
  computed by the pure function `DialPanelGeometry`.
- Panel width is fixed at 380pt; dynamic labels truncate instead of
  stretching the window.
- One key profile: the AI/System split and the `switchProfile` action are
  gone. Existing configs migrate on launch.
- Device backup is fully automatic (debounced write on binding changes, on
  connect, and on first launch). No write button, no confirmation.
- Power polling adapts to visibility: every 3 heartbeats while the panel is
  open, every 30 while closed (and every 8 when the device is silent).
- `build-app.sh` signs with the first available **Apple Development**
  identity so TCC grants survive rebuilds; ad-hoc is only a fallback.

### Fixed

- Panel opening as a huge blank rectangle when a menu-bar manager
  (Bartender/Ice) moved or hid the status item — the popover had been given
  an off-screen anchor.
- Permission switches that "did nothing": ad-hoc signatures changed the
  code identity on every build and silently invalidated the grants.
- Charging state not updating until the panel was clicked (the device does
  not push power events).
- Usage-chart hover reporting the last column regardless of pointer position
  (`NSTrackingArea.inVisibleRect` was overriding the per-column rect).
- Usage retention keeping months-old days for infrequent users; pruning is
  now a calendar window.
- The last two seconds of usage events being lost on quit.
- Guide window click-to-dismiss not working over the cards.
- Lights card squeezing the state chip to "Wo…" and clipping the Connect
  button at 380pt; the card now uses three rows and the chip cannot be
  compressed.
- Drawn gauges being invisible to VoiceOver.

### Removed

- Profile switching, long-press action, and the inline (collapsible) light
  guide strip.

## [1.0.0] — 2026-11-21

Initial public release: seven bindings on the Ulanzi AU05, agent status
lights with multi-session arbitration, hooks for seven agents, zero
third-party dependencies.
