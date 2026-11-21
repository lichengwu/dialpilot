# DialPilot User Guide

> Companion reading: README (features and install), [protocol.md](protocol.md) (HID protocol and reverse-engineering notes, Chinese), [led-design.md](led-design.md) (light design, Chinese).
> Goal: install, configure, verify and troubleshoot without reading the code. 中文版见 [user-guide.md](user-guide.md).

## 1. Install and upgrade

### First install

1. Quit Ulanzi Studio completely (two hosts cannot drive the device at once).
2. Build and sign:

   ```sh
   ./build-app.sh
   # or pin a certificate:
   DIALPILOT_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./build-app.sh
   ```

   The script picks your first Apple Development identity automatically and only falls back to ad-hoc when none exists.
   **An ad-hoc signature changes identity on every rebuild**, so macOS silently invalidates the Input Monitoring / Accessibility grants you already gave.
3. The artifact is `.build/app/DialPilot.app` (includes `Contents/MacOS/dialpilotctl`). Copy it to `/Applications/` and launch.
4. System Settings → Privacy & Security → enable **Input Monitoring** and **Accessibility**.
5. On first launch, an existing VibeKey Lite configuration is migrated automatically.

### Upgrading (keep the grants)

```sh
osascript -e 'tell application "DialPilot" to quit'
ditto ".build/app/DialPilot.app" "/Applications/DialPilot.app"
codesign --verify --strict "/Applications/DialPilot.app"
open "/Applications/DialPilot.app"
```

Signed with the same identity → the grants carry over. `dialpilotctl status` should return `state=idle` afterwards.

## 2. Before first use (one-time, in Ulanzi Studio)

DialPilot talks to the device directly over HID and does **not** need Ulanzi Studio running. For a brand-new AU05, do this once:

1. Install Ulanzi Studio and connect the AU05 over USB.
2. Apply any firmware update it offers. DialPilot never touches firmware — it only writes the verified light-control group and the six key slots.
3. Confirm the knob and three buttons produce their factory actions in Studio (verifies the hardware and gives you a known-good baseline).
4. Quit Studio completely (⌘Q — closing the window is not enough) and keep it closed.

No account binding or key mapping in Studio is required — DialPilot writes its own six-slot backup on first launch.

## 3. The panel

Click the menu-bar icon. Width is fixed at 380pt; height follows the content. Cards top to bottom:

| Area | Contents |
| --- | --- |
| Device | Battery ring (big number + %), connection / permission / responsiveness state, which agent session currently owns the LEDs |
| Keys | One dropdown per control: a preset action or "Record keyboard shortcut…" |
| Lights | All On / Off / Smart, live state chip, preview dropdown, Connect Agent, guide button |
| Usage | Today / all-time counts, most-used control, 7-day bar chart (hidden until the first event) |
| Footer | The only maintenance button: Quit |

Dismiss with **Esc**, **a click anywhere outside**, or **⌘-Tab**.

Positioning: the panel is a window DialPilot positions itself, not a system popover. When a menu-bar manager (Bartender, Ice) moves or hides the icon, the panel follows the icon's live position; if the icon is gone entirely, the panel closes instead of leaving a blank window behind.

## 4. Menu-bar icon semantics

The icon only reports exceptions. No badge means everything is ready.

| Icon | Meaning |
| --- | --- |
| Normal device glyph | Device ready, permissions granted |
| Orange dot | Missing Input Monitoring or Accessibility — gestures/lights are stuck |
| Red dot | Low battery (device reports low, or < 20% and not charging) |
| Green dot | Charging (disappears when full) |
| Faded dashed glyph | Device absent, or switched off (USB present but silent) |

One badge at a time. Priority: absent > permission > low battery > charging > normal.

## 5. Permissions

| Permission | Why | Where |
| --- | --- | --- |
| Input Monitoring | Read knob/button events over HID | System Settings → Privacy & Security → Input Monitoring |
| Accessibility | Send the configured key actions to the frontmost app | System Settings → Privacy & Security → Accessibility |

- When either is missing, the panel shows a banner with one-click buttons that open the exact pane (and trigger the native prompt where macOS supports it).
- Status is re-checked every time the panel opens; reopen it after granting.
- **Input Monitoring** sometimes needs an app restart — quit DialPilot and launch it again.
- If grants keep disappearing, check whether you are building ad-hoc (see §1).

## 6. Configuration and automatic backup

Config file: `~/Library/Application Support/DialPilot/config.json`

| Field | Type | Meaning |
| --- | --- | --- |
| `activeProfile` | `"a"` | Single-profile product; always a. Legacy b is migrated on launch |
| `offlineProfile` | `"a"` / absent | Marks a completed six-slot device backup; absent = not written yet, the app will write it |
| `profileA` | object | Key mappings: control name → action |
| `needsHardwareSync` | bool | Internal flag: whether a full six-slot write is pending. **Do not edit by hand** |
| `lightMode` | `"allOn"` / `"off"` / `"smart"` | Light mode, default smart |

Controls: `knobPress` (single), `knobDoublePress`, `knobLeft` / `knobRight`, `topButton` / `middleButton` / `bottomButton`.

Actions come in two shapes:

- Preset string: `"selectAll"`, `"returnKey"`, `"volumeUp"`, … (the full set is the UI dropdown).
- Shortcut object: `{"type":"shortcut","shortcut":{…}}` — generate it with the recorder (max 4 keys, left/right modifiers distinguished).

Note: `fnDoubleTap` and `voiceInput` are app-only actions and cannot be stored in the device's six slots. The old `switchProfile` action is gone; an existing binding to it decodes as "do nothing".

**Device backup is automatic**: change any binding and the app writes the six slots after a 1.5 s debounce; if the device is away it writes when it appears. There is no write button.

## 7. Agent lights

### States

| State | Pattern | Meaning |
| --- | --- | --- |
| idle / sleeping | all off | idle |
| thinking | knob slow blink 1.2 s | thinking |
| working | knob solid | working |
| attention | middle key lit 10 s, auto-off | turn complete |
| notification | middle+bottom fast blink 0.6 s | **needs your approval** (highest priority) |
| error | all LEDs flash 3×, then restore | error |
| sweeping | three-LED chase 0.5 s | context compaction |

The voice-key LED does not participate in status display (firmware key feedback; a flash on press/release is normal). The in-panel "guide" opens a full-screen illustrated explainer: ←/→ or horizontal swipe to page, click anywhere or Esc to close.

### Install / uninstall

**In the panel**: Lights card → "Connect Agent…" → pick an agent → Connect / Uninstall.

- Detection runs first; if the software is missing you are told to install it and **nothing is written**.
- Connect = back up the existing config (`.bak-dialpilot-<timestamp>`) → add only entries tagged `dialpilot` → read back and verify.
- Uninstall = remove only tagged entries; your own hooks stay untouched.

**CLI**:

```sh
CTL="/Applications/DialPilot.app/Contents/MacOS/dialpilotctl"
"$CTL" detect                          # per-agent install/connection status
"$CTL" install-hooks --agent qoder     # claude-code|qwen-code|qoder|codebuddy|codex|dsh
"$CTL" uninstall-hooks --agent qoder
"$CTL" led --state working             # manual state (testing)
"$CTL" led --restore                   # restore the factory light baseline
"$CTL" status                          # current state + active sessions
```

- `codebuddy` writes `~/.workbuddy/settings.json` (WorkBuddy's real path).
- `codex` also enables `[features] hooks=true` in `config.toml` and **requires `/hooks` approval inside a session**.
- `dsh` writes a tagged block in `~/.dsh/profiles/web/cordis.patch.yml`; restart to apply.
- Hooks always print `{}` and exit 0 — they never block the agent.

### QwenWork (enterprise premium only)

The personal edition has no hooks. Enterprise: click Connect in the panel → a loopback listener starts (`127.0.0.1:27950`) → copy the seven-event config → paste each event into the admin console → run a task and watch the lights. Uninstall = stop the listener + clear the rules. The listener never starts on its own and stops when the app quits.

### Multi-session arbitration (not a bug)

With several sessions running, the LEDs show only the highest priority: approval > error > compaction > thinking > working > done > idle. Sessions silent for 120 s are dropped. The panel says which agent/session owns the LEDs; `dialpilotctl status` prints the full list (`*` marks the winner).

For a clean light test, uninstall the hooks first — real sessions will otherwise keep overriding manual states.

## 8. Usage statistics

- Counted: performed control events (knob detents, single/double press, button taps, hold start).
- Stored in `~/Library/Application Support/DialPilot/usage.json`, 90 days of daily detail, lifetime totals kept forever.
- Privacy: no network, no device or user identifiers — only control names and dates.
- Hover any chart column for full date · count · that day's top control.

Delete `usage.json` to reset. A missing or corrupt file starts from empty and never blocks the app.

## 9. Acceptance scripts

```sh
./scripts/acceptance.sh offline   # offline: all automatic assertions (mock device)
./scripts/acceptance.sh live      # on-device: assertions + manual checks
```

Manual items in live mode accept `s` to skip; they never auto-pass.

## 10. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `dialpilotctl` says DialPilot is not running | App not launched or socket not ready; start it and retry after 3 s |
| Lights completely dead | ① Ulanzi Studio running (quit it) ② device asleep (press any key; replays within 10 s) ③ three consecutive write failures suspended it (same fix) |
| Device is off but the panel showed "connected" with an old percentage | Fixed: liveness now requires an answered power query; two silent polls show "not responding" and clear the battery |
| Menu-bar icon turns dashed after switching the knob off | Expected: USB is enumerated but the firmware is silent, so it is treated as absent |
| Panel in a weird spot / huge blank area | Old `NSPopover` sizing bug; the panel is now self-owned and sized to content. If it still happens, attach `debug.log` |
| Clicking the icon does nothing with Bartender/Ice | When the icon is stashed, the panel anchors at the pointer; make the icon visible first, or pin DialPilot in that tool |
| A manual state gets "stolen" | Real-hook arbitration (see §7); uninstall hooks for clean tests |
| A light turns itself off after ~10 s | Expected `attention` behavior (completion bell) |
| The voice-key LED flashes on its own | Firmware key feedback; the host cannot control it |
| Grants keep disappearing | Ad-hoc signature; rebuild with one stable identity (see §1) |
| Hooks installed but nothing happens | Codex needs `/hooks` approval; DSH needs a restart; others need a new session |
| Device buttons stopped working | After an unexpected app exit the firmware reverts to native; relaunch the app |

Logs: `~/Library/Application Support/DialPilot/debug.log`.

## 11. Red lines

- Never touch firmware upgrade / pairing / reset. Device writes are limited to the 0x0B light group and the verified six-slot write.
- Restore the baseline after testing: `dialpilotctl led --restore`.
- Never run Ulanzi Studio and DialPilot at the same time.
