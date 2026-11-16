# Sleep Manager

A macOS menu bar app that puts the "don't sleep" commands one click away. No Dock icon, no window.

| Menu item | What it runs |
|---|---|
| Keep Awake | `caffeinate -d` (screen and Mac stay awake while the lid is open) |
| Lid Closed Mode | `sudo pmset -a disablesleep 1` / `0` (Mac keeps working with the lid shut) |
| Real Sleep on Battery | `sudo pmset -b powernap 0 tcpkeepalive 0 womp 0`; off restores Apple's `powernap 1 tcpkeepalive 1 womp 0` |
| Last sleep (length): woke N times | Read from `pmset -g log`: how long the last sleep lasted, its brief "DarkWakes", their main cause, battery drop |
| Turn Screen Off Now | `pmset displaysleepnow` |
| What's Keeping It Awake | `pmset -g assertions`, as a list |

The icon is an open laptop when nothing is on, a filled screen while Keep Awake is on, and a **red closed laptop while
Lid Closed Mode is on**. The red icon is the only reminder: nothing switches off by itself.

Built for one Mac running macOS 26 with the Command Line Tools (`xcode-select --install`). Xcode is not needed.

## Install

```bash
scripts/install.sh
```

Builds the app, copies it to `/Applications/SleepManager.app`, adds a login item
(`~/Library/LaunchAgents/local.sleep-manager.plist`) and starts it. Run it again after changing the code.

## One-time setup for Lid Closed Mode and Real Sleep

```bash
sudo scripts/setup.sh
```

Installs `/etc/sudoers.d/sleep-manager`, which lets your user run exactly these four commands without a password, and
nothing else:

- `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`
- `/usr/bin/pmset -b powernap 0 tcpkeepalive 0 womp 0` and `/usr/bin/pmset -b powernap 1 tcpkeepalive 1 womp 0`

The rule is checked with `visudo` before it is installed. Until it's there, the item is greyed out with "Setup needed"
under it. If you ran the setup before Real Sleep existed, run it again.

## Behaviour worth knowing

- **Quitting the app** stops Keep Awake (its `caffeinate` ends with the app) but leaves Lid Closed Mode as it is. While
  Lid Closed Mode is on, Quit shows "Lid Closed Mode stays on".
- **The icon follows the real setting.** It reads `pmset -g` at launch, every time the menu opens and every 30 seconds,
  so a change made in Terminal shows up.
- **"What's Keeping It Awake"** hides WindowServer's "user is active" entries, which only mean the keyboard or mouse
  was touched.
- **Real Sleep on Battery** stops Power Nap, TCP keep-alive and wake for network access while asleep on battery, so the
  Mac stops waking about once a minute for Wi-Fi/Bluetooth traffic (each wake lets apps like Dropbox run). On mains
  power nothing changes. The cost: **Find My can't locate the Mac while it's asleep on battery**. A dash instead of a
  checkmark means the settings were changed elsewhere; clicking it switches Real Sleep fully on. To undo it by hand:
  `sudo pmset -b powernap 1 tcpkeepalive 1 womp 0`.
- **"Last sleep"** is read at launch and after each wake (the log takes a few seconds to read), not when the menu
  opens.

To check by hand whether sleep is disabled:

```bash
pmset -g | grep SleepDisabled
```

## Develop

```bash
scripts/build.sh    # build/SleepManager.app, ad-hoc signed
scripts/test.sh     # unit tests (parsing of pmset output)
```

`scripts/test.sh` wraps `swift test` because the Command Line Tools keep the Swift Testing macro plugin in a folder
SwiftPM doesn't search.

| Path | What's in it |
|---|---|
| `Sources/SleepCore/` | Running the commands and parsing their output; no AppKit, so it's testable |
| `Sources/SleepManager/` | The menu bar app (AppKit `NSStatusItem` + `NSMenu`) |
| `Resources/` | Menu bar icons (SVG, concept "1b Lid" from Claude Design) |
| `design/handoff/` | The Claude Design handoff: mockups, all three icon concepts, notes |
| `docs/` | Design doc and the Claude Design brief |

## Uninstall

```bash
scripts/install.sh uninstall
```

```bash
sudo scripts/setup.sh uninstall
```

The first removes the app and the login item; the second removes the sudoers rule. Before uninstalling, make sure
Lid Closed Mode is off (the icon isn't red), or run `sudo pmset -a disablesleep 0` afterwards.
