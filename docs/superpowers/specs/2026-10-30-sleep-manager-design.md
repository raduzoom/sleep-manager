# Sleep Manager: design and phased plan

Date: 2026-10-30. Status: draft, awaiting approval. Nothing is built yet.

## Why

The user runs two sets of Terminal commands to keep their Mac working, often while Claude finishes a long task:

- `caffeinate -d` to keep the Mac awake with the lid open.
- `sudo pmset -a disablesleep 1` to keep it working with the lid closed, then `sudo pmset -a disablesleep 0` to switch
  normal sleep back on.

Typing these, and the password for `pmset`, is friction. Forgetting the second `pmset` drains the battery and heats the
laptop: on 2026-10-30 `SleepDisabled` was still `1` without the user knowing.

The goal is to put these commands one click away in the menu bar, with an icon that turns reddish while lid-closed mode
is on, so the user notices it.

## Goals

- Menu bar app, one click to switch each mode on or off.
- **Keep awake**: runs `caffeinate -d`, stops it when switched off.
- **Lid closed**: runs `pmset -a disablesleep 1` / `0`, with no password prompt after a one-time setup.
- **Screen off now**: runs `pmset displaysleepnow` (screen goes dark, Mac keeps working).
- **What's keeping it awake**: shows `pmset -g assertions` in a readable list.
- Icon turns reddish while Lid closed is on. This is the only reminder.
- The icon always matches reality, including after a restart, a crash, or a change made from Terminal.
- Simple interface.

## Non-goals

- No automatic switch-off: no timers, no "turn off when the battery is low", no notifications. The user decided the red
  icon is enough.
- No timed caffeinate, no "until process exits", no battery percentage (offered, not chosen; easy to add later).
- No distribution: built for the user's own Mac. No Apple developer account, no notarization, no App Store.
- No Dock icon, no Cmd-Tab entry.

## Anti-goals (would count as failure even if it works)

- The icon shows "off" while `SleepDisabled` is really `1`. That is the exact problem this app exists to prevent.
- A password prompt on every toggle.
- Passwordless root for anything beyond the exact `pmset` commands listed in `scripts/setup.sh`.
- A busy or settings-heavy interface.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Forgotten Lid closed mode | Do nothing; the reddish icon is the reminder |
| Admin rights | One-time setup, then no password prompts |
| Dock icon | None; menu bar only |
| Audience | Just the user's Mac for now |
| Extra commands | `pmset displaysleepnow` and `pmset -g assertions` |
| App quits or crashes while Lid closed is on | Lid closed stays on. App starts at login and on launch reads the real `pmset` value, so the red icon comes back |
| Claude Design output | The full visual design: icon in all states, the dropdown menu, the assertions view |
| Icon concept | 1b Lid from the Claude Design handoff (open laptop / filled screen / red `#E5372E` closed laptop); SVGs in `Resources/` |
| Dropdown style | Standard macOS menu (like Wi-Fi/Bluetooth): checkmarks for the two modes, assertions list in a submenu |
| Real Sleep (added 2026-11-07, `plans/real-sleep.md`) | Toggle "Real Sleep on Battery": `pmset -b powernap 0 tcpkeepalive 0 womp 0`, off restores Apple's battery defaults `powernap 1 tcpkeepalive 1 womp 0`. Battery only, so Find My and network wake still work on mains |
| Last sleep line | Grey "Last sleep (length): woke N times (reason) · A% → B%" from `pmset -g log`, read at launch and after each wake |
| Icon for Real Sleep | Unchanged; red stays reserved for Lid closed |

## Calls made by Claude (check these)

- **Stack:** Swift 6 + AppKit `NSStatusItem`/`NSMenu` (changed from SwiftUI `MenuBarExtra` in Phase 2: AppKit gives a
  reliable "menu is opening" hook to re-read state, and keeps the red icon from being tinted as a template), built with
  Swift Package Manager and a small script that assembles the
  `.app` bundle (`LSUIElement = YES`) and ad-hoc signs it. This Mac has the Command Line Tools and Swift 6.4 but no
  Xcode, so the build must not need Xcode. Minimum macOS 26.
- **One-time setup:** a script the user runs once with `sudo` that installs `/etc/sudoers.d/sleep-manager`, allowing
  only `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1` for the user `test` with no password,
  validated with `visudo -cf` before it is installed. The app calls `sudo -n /usr/bin/pmset ...`. If that fails, the
  menu shows "Setup needed" with the one command to run, instead of failing silently.
- **Keep awake and Lid closed are independent** and can both be on. When both are on, the icon is reddish (Lid closed
  wins).
- **Keep awake runs `caffeinate -d -w <app pid>`** as a child process, so it ends by itself if the app quits or
  crashes. That's harmless, since Keep awake has no lasting effect. Lid closed, by contrast, survives the app on purpose.
- **Keep awake state** reflects only the app's own `caffeinate`. A `caffeinate` started from Terminal shows up in
  "What's keeping it awake" but doesn't change the icon.
- **State sync:** the app reads `pmset -g` at launch, each time the menu opens, and on a ~30 s timer, so changes made
  from Terminal show up.
- **Launch at login:** a LaunchAgent (`~/Library/LaunchAgents/local.sleep-manager.plist`, `RunAtLoad`, no
  `KeepAlive`) that runs `open /Applications/SleepManager.app`, installed by `scripts/install.sh`. Chosen over
  `SMAppService` because the app is ad-hoc signed and its signature changes on every rebuild. No menu toggle; uninstall
  with `scripts/install.sh uninstall`.
- **Screen off now** is always available and runs the plain command. It only keeps the Mac working if Keep awake or
  Lid closed is on; with both off, the Mac sleeps after its normal idle time. In that case the menu item carries a
  short hint ("Mac may sleep") rather than being disabled or starting its own keep-awake.
- **Icon states:** three. Off is a neutral monochrome template icon. Keep awake is a distinct but calm variant. Lid
  closed is reddish and not a template image, so it stays red in light and dark menu bars.

## Left to the builder

- Exact process plumbing (`Process`, output parsing of `pmset -g` and `pmset -g assertions`).
- How each assertion line is worded and grouped inside the submenu, within whatever Claude Design returns.
- Project layout, test approach for the parsing code.

## Phased plan

Each phase ends with something the user can check. The user commits by hand; no phase commits or pushes.

### Phase 1: Claude Design handoff

Write `docs/design/claude-design-brief.md`, a self-contained brief the user pastes into Claude Design. It covers:

- What the app is and who it's for, in two or three lines.
- The three icon states (off, Keep awake, Lid closed in red/reddish), how they should read at 16–22 pt in light and dark
  menu bars, and the macOS menu bar conventions to follow.
- That the dropdown is a **standard macOS menu** (system font, checkmarks, submenus), not a custom panel, so the
  mockups must only use what a native menu can show. The dropdown menu contents, in order: status line, Keep awake toggle, Lid closed toggle, Screen off now, What's
  keeping it awake, the "Setup needed" state, Quit.
- The "What's keeping it awake" submenu with realistic sample data (taken from a real `pmset -g assertions` run).
- What to send back: icon assets as SVG or PDF (vector, one file per state), plus mockups of the menu in each state and
  of the assertions submenu. Most of the design work is the three icon states.

**Done when:** the user has the design back and has dropped the assets and mockups into `design/`.

### Phase 2: Working core with placeholder icons

Can start while Phase 1 is with Claude Design, since it doesn't depend on the visuals.

- SwiftPM project, build script producing `SleepManager.app`, no Dock icon.
- One-time setup script for the sudoers rule, with validation and an uninstall option.
- Standard menu with Keep awake, Lid closed, Screen off now, and the assertions submenu, all working, using SF Symbols as
  placeholder icons (red for Lid closed).
- State read from `pmset` at launch, on menu open, and on a timer.

**Done when:** the user can switch each mode from the menu, `pmset -g | grep SleepDisabled` agrees with the icon, and
changing it from Terminal updates the icon within ~30 s.

### Phase 3: Apply the design

- Replace placeholder icons with the Claude Design assets.
- Adjust menu wording, order, and the assertions submenu to match the mockups.

**Done when:** the app matches the mockups in light and dark mode.

### Phase 4: Make it stick

- Launch at login.
- "Setup needed" state when the sudoers rule is missing.
- Install step (copy to `/Applications`) and a short README: build, setup, uninstall (remove the app, the login item,
  and `/etc/sudoers.d/sleep-manager`).

**Done when:** after a reboot the app is in the menu bar, and if `SleepDisabled` was left at `1` the icon is red.
