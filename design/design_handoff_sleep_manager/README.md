# Handoff: Sleep Manager (macOS menu bar extra)

## Overview
Sleep Manager is a macOS 26 menu bar utility with no Dock icon and no window. It has one status item (an icon) and a standard dropdown menu. Two independent modes:

| Mode | Effect | Command |
|---|---|---|
| Keep Awake | Mac and screen stay awake while the lid is open | `caffeinate -d` (keep the child process alive; kill it to stop) |
| Lid Closed Mode | Mac keeps running with the lid shut | `sudo pmset -a disablesleep 1` / `0` (needs one-time admin setup via `setup.sh`) |

Either, both or neither can be on. **The most important requirement: when Lid Closed Mode is on, the menu bar icon is red.** It is the only reminder that the Mac won't sleep.

## About the design files
`Sleep Manager Design.dc.html` is a **design reference built in HTML**, not production code. Rebuild it natively in Swift with AppKit (`NSStatusItem` + `NSMenu`), or SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.menu)`. Every mockup uses standard menu features only: disabled rows, checkmarks, separators, item subtitles, a submenu and a key equivalent. Don't build a custom panel. The page's surrounding presentation (serif headings, off-white cards) is review chrome and is not part of the app.

To view it, open the `.dc.html` file in a browser with `support.js` next to it. Brand fonts won't load outside the design project; that only affects the review chrome.

## Fidelity
- **Icons:** high fidelity. Use the SVGs in `icons/` as shipped.
- **Menu:** high fidelity for **structure, wording, order and states**. Visual styling (font, row height, highlight colour, materials, corner radius) must come from the system `NSMenu`, not from the mock's CSS approximations.

## Icon concept: decision pending
Three concepts were designed. **1b Lid** is the current default in the design file. Confirm the final choice with the designer; all three ship in the same format, so switching means changing only the asset folder.

- `icons/1a-crescent/`: outline moon (off), filled moon (keep awake), red filled moon with dot (lid closed)
- `icons/1b-lid/`: open laptop outline (off), filled screen (keep awake), red closed laptop with three activity marks (lid closed)
- `icons/1c-eye/`: closed eye (off), open eye (keep awake), solid red eye (lid closed)

Each folder has `icon-off.svg`, `icon-keep-awake.svg`, `icon-lid-closed.svg`. Specs:
- 18 × 18 viewBox, artwork about 16 pt tall. Draw the status item image at **18 × 18 pt**.
- `icon-off` and `icon-keep-awake`: pure black on transparent. Load them as **template images** (`image.isTemplate = true`) so macOS tints them for light/dark bars and wallpaper.
- `icon-lid-closed`: **red `#E5372E`**, `isTemplate = false`, so it stays red on light and dark bars. Each state also differs in shape, so the meaning doesn't depend on colour alone.
- Convert to PDF or an asset catalog Symbol Image if preferred; keep "Preserve Vector Data" on.

Icon state logic:
```
icon = lidClosedOn ? lidClosed : (keepAwakeOn ? keepAwake : off)
```

## Menu structure (top to bottom)

```
[status row]                               disabled
─────────────
Keep Awake                                 checkmark when on
Lid Closed Mode                            checkmark when on; disabled + subtitle when setup missing
─────────────
Turn Screen Off Now                        subtitle "Mac may sleep" when neither mode is on
What's Keeping It Awake                  ▸ submenu
─────────────
Quit Sleep Manager                    ⌘Q
```

### Status row (disabled `NSMenuItem`, not clickable)
| State | Text |
|---|---|
| Neither on | `Sleeping normally` |
| Keep Awake only | `Keeping awake, screen on` |
| Lid Closed on (alone or with Keep Awake) | `Lid Closed Mode on: Mac won't sleep` |

### Items and behaviour
- **Keep Awake**: toggles `caffeinate -d`. `state = .on` shows the checkmark.
- **Lid Closed Mode**: toggles `pmset -a disablesleep 1/0`. Checkmark when on.
  - **Setup missing:** `isEnabled = false`, `subtitle = "Setup needed: run setup.sh once"` (`NSMenuItem.subtitle`, macOS 14.4+). No extra row.
  - On launch, read the real value (`pmset -g` → `SleepDisabled`) so the checkmark and red icon reflect reality even if the app restarted.
- **Turn Screen Off Now**: runs `pmset displaysleepnow`. When neither mode is on, set `subtitle = "Mac may sleep"`; otherwise no subtitle.
- **What's Keeping It Awake**: submenu, rebuilt on open (`menuNeedsUpdate(_:)` / `menuWillOpen(_:)`).
- **Quit Sleep Manager**: key equivalent `q` (⌘Q). Decide with the user whether quitting turns off active modes. Recommended: turn Keep Awake off (the caffeinate child dies anyway) and leave Lid Closed Mode as it is, but warn if it's on.

### "What's Keeping It Awake" submenu
Source: `pmset -g assertions` (or `IOPMCopyAssertionsByProcess`). One disabled-looking but readable row per assertion:
- **Title:** process name, e.g. `caffeinate`
- **Subtitle:** `<what it prevents> · <duration>`, e.g. `Display sleep · 29 h 28 min`
- **Image:** SF Symbol `display` for display-sleep assertions, `moon` for system/idle-sleep assertions (template, 15 pt)
- **Sort:** longest duration first
- **Hide** WindowServer's `UserIsActive` assertion (noisy). The design file has a toggle that shows it for comparison.
- **Empty:** single disabled row `Nothing is keeping it awake`

Sample data used in the mocks:
| Title | Subtitle | Symbol |
|---|---|---|
| caffeinate | Display sleep · 29 h 28 min | display |
| powerd | System sleep while display is on · 5 h 32 min | moon |
| Claude | Idle system sleep · 3 h 33 min | moon |
| WindowServer *(hidden)* | User is active · a few seconds | moon |

Assertion-type mapping suggestion: `PreventUserIdleDisplaySleep` → "Display sleep"; `PreventUserIdleSystemSleep` → "Idle system sleep"; `PreventSystemSleep` → "System sleep"; `PreventSleepWhileDisplayOn`-style powerd entries → "System sleep while display is on"; `UserIsActive` → hidden. Durations: `X h Y min`, `Y min`, or `a few seconds` under one minute.

## State management
- `keepAwakeOn: Bool`: true while the caffeinate child process is running.
- `lidClosedOn: Bool`: mirrors `pmset` `SleepDisabled`, read at launch and after each toggle.
- `setupInstalled: Bool`: whether the privileged helper/sudoers rule from `setup.sh` exists. If false, Lid Closed Mode is disabled.
- Derived: icon image, status-row text, Turn Screen Off subtitle.
- Refresh `lidClosedOn` when the menu opens, in case it was changed outside the app.
- `LSUIElement = YES` (no Dock icon).

## Design tokens
- Lid closed red: **`#E5372E`** (works on both light and dark bars; alternatives considered: `#FF453A`, `#D9302A`, `#F0503C`).
- Everything else is native: system font, menu metrics and colours come from AppKit.

## Mockup states in the design file (light + dark each)
1. Neither mode on
2. Keep Awake on
3. Lid Closed Mode on
4. Both on (red icon, both checked, lid status text)
5. Setup needed
6. Submenu open with sample data
7. Submenu open, empty

## Files
- `Sleep Manager Design.dc.html`: icon concept board, all menu mockups, final wording. Tweaks: `concept`, `red`, `hideSystemEntries`.
- `support.js`: runtime needed to open the design file.
- `icons/<concept>/icon-*.svg`: production icon assets.
