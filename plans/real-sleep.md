# Real Sleep on Battery: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Per `~/CLAUDE.md` § Always: never commit unless the user asks. There are no commit steps.

Date: 2026-11-07. Status: approved with the proposed defaults. Phases 1–4 are built. Phase 5 (the two sleep tests)
is waiting on the user.

**Goal:** One menu item that stops the Mac waking itself about once a minute while asleep on battery, plus a line that
shows how many times it woke during the last sleep.

**Architecture:** Parsing lives in `SleepCore` with tests on real `pmset` output, as it does now. The app runs two exact
`pmset` commands through `sudo -n`, allowed by a wider sudoers rule from `scripts/setup.sh`. The wake count comes from
`pmset -g log`. That command takes about 4.6 s and prints 14 MB, so it runs off the main thread and only at launch and
after each wake.

**Tech Stack:** Swift 6.2, AppKit `NSMenu`, Swift Testing, zsh scripts. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-30-sleep-manager-design.md` (the app). This plan adds one feature to it.

## Why (evidence from this Mac)

On 2026-11-06 the battery went from 2% to 1% while the Mac kept switching between a "DarkWake" and sleep every 15 to
60 s. Each DarkWake gives apps like Dropbox a few seconds to run. From `pmset -g log` (the whole log, 2,055 DarkWakes):

| Count | Wake reason |
|---|---|
| 1,595 | `smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/` |
| 102 | `... wifibt SMC.OutboxNotEmpty nub-spmi0.0x3E/` |
| 7 | `... wifibt SMC.OutboxNotEmpty bluetooth-pcie/` |
| a few | `NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance` (timed wakes, harmless) |

Each sleep entry says `'Maintenance Sleep':TCPKeepAlive=active`. Current `pmset -g custom`:

| Setting | Battery | AC (mains) |
|---|---|---|
| `powernap` | 1 | 1 |
| `tcpkeepalive` | 1 | 1 |
| `womp` | **0** (already off) | 1 |

## Decisions to confirm (proposed defaults in bold)

| # | Question | Proposed | Why |
|---|---|---|---|
| D1 | Battery only (`-b`) or both (`-a`)? | **Battery only** | The drain only hurts on battery. On mains, Find My, wake for network access and Power Nap backups keep working. Cost: a lost Mac asleep on battery can't be found by Find My. |
| D2 | A one-off command, or a toggle in the menu? | **Toggle with a checkmark** | Easy to undo, and it matches Keep Awake and Lid Closed Mode. A setting changed elsewhere shows up in the menu. |
| D3 | What "off" restores | **Apple's battery defaults: `powernap 1 tcpkeepalive 1 womp 0`** | These are this Mac's current battery values. Nothing needs to be stored. |
| D4 | Menu name | **"Real Sleep on Battery"** | Your own phrase. Other options: "Deep Sleep on Battery", "Block Wakes on Battery". |
| D5 | Show "Last sleep: woke N times"? | **Yes, as one grey line under the toggle** | It shows whether the fix works without opening Terminal. |
| D6 | Change the menu bar icon when Real Sleep is off? | **No** | The spec's anti-goal is a busy interface, and the red icon stays reserved for Lid Closed Mode. |

If D1 becomes "both", Task 3's two commands change to `-a` and "off" needs a third command (`-c womp 1`), because
battery and AC have different `womp` defaults.

## Global Constraints

- macOS 26, Command Line Tools only, no Xcode (`Package.swift`, `scripts/build.sh`).
- Passwordless root only for exact command lines. sudoers matches the whole argument list, so the app must send the
  arguments in exactly the order the rule lists them.
- `SleepCore` stays free of AppKit.
- Exact commands: on = `/usr/bin/pmset -b powernap 0 tcpkeepalive 0 womp 0`, off =
  `/usr/bin/pmset -b powernap 1 tcpkeepalive 1 womp 0`.
- Never run `pmset -g log` on the main thread.
- Run tests with `scripts/test.sh`, not plain `swift test`.

## Review Focus

1. **Settings changed in System Settings** (for example only `powernap` turned off). The menu shows a mixed checkmark,
   and clicking it switches Real Sleep fully on. Covered in Task 1 (`partialWhenSettingsDisagree`).
2. **Sudoers rule installed before this feature.** Lid Closed Mode keeps working. Real Sleep is greyed out with "Setup
   needed: run setup.sh again". Covered in Task 3 (each feature has its own setup check) and Task 4 (manual check).
3. **No battery** (desktop Mac) or **no full wake in the log yet** (log rotated, fresh boot). The item or the line is
   hidden. It doesn't crash or show "0 times". Covered in Task 1 (`noBatterySection`) and Task 2 (`nilWithoutFullWake`).
4. **`pmset` exits 0 but prints a warning** when `tcpkeepalive` is turned off (it warns about Find My). Success is
   decided by the exit status, then the settings are read again. A warning is never treated as an error. Covered in
   Task 3.
5. **Slow wake log.** At 4.6 s, the menu must open at once and show the last result it has, or nothing. Covered in
   Task 4 (loaded in the background, cached).

---

## Phase 0: Check that the fix works, by hand (no code)

> **Replaced by Phase 5** (the user's request, 2026-11-07). The feature is built first, then checked with two sleep
> tests, one with it on and one with it off. The steps below are kept as the manual fallback.

The pasted diagnosis is likely right, but `wifibt` wakes can also come from Bluetooth devices. Before building UI for
it, check one night.

- [ ] **Step 1:** The user runs the exact "on" command (password at the `Password:` prompt; nothing shows while
  typing):

```bash
sudo pmset -b powernap 0 tcpkeepalive 0 womp 0
```

- [ ] **Step 2:** Check that it applied. Expected under `Battery Power:`: `powernap 0`, `tcpkeepalive 0`, `womp 0`.

```bash
pmset -g custom
```

- [ ] **Step 3:** Leave the Mac asleep on battery overnight. The next day, count DarkWakes since the last sleep started
  (replace the date):

```bash
pmset -g log | grep DarkWake | grep -c "^2026-11-08"
```

**Done when:** the night shows a handful of timed `rtc` wakes rather than hundreds of `wifibt` wakes, and the battery
drop is small. If `wifibt` wakes continue, stop and rethink (Bluetooth wake, a specific device) before Phase 1.

## Phase 1: Read the settings and the wake log (SleepCore, TDD)

### Task 1: Parse `pmset -g custom` into Real Sleep state

**Files:**
- Modify: `Sources/SleepCore/PowerSettings.swift`
- Test: `Tests/SleepCoreTests/SleepCoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum PowerSource: String, Sendable { case battery = "Battery Power", ac = "AC Power" }`
  - `public struct NetworkWakeSettings: Equatable, Sendable { public let powernap, tcpkeepalive, womp: Bool }`
  - `public enum RealSleepState: Equatable, Sendable { case on, off, partial }`
  - `extension NetworkWakeSettings { public var realSleep: RealSleepState }`. `.on` when all three are false, `.off`
    when `powernap` and `tcpkeepalive` are both true, `.partial` otherwise. (`womp` alone doesn't make it partial,
    because Apple's battery default is `womp 0`.)
  - `PowerSettings.networkWake(fromPmsetCustomOutput: String) -> [PowerSource: NetworkWakeSettings]`. A source missing
    any of the three keys is left out.

- [ ] **Step 1: Write the failing tests**, with the real `pmset -g custom` output above as the fixture:
  - `readsBatteryAndACSettings`: battery == `(true, true, false)`, ac == `(true, true, true)`, `battery.realSleep == .off`
  - `realSleepOnWhenAllOff`: `NetworkWakeSettings(powernap: false, tcpkeepalive: false, womp: false).realSleep == .on`
  - `partialWhenSettingsDisagree`: `(false, true, false).realSleep == .partial`
  - `noBatterySection`: an output with only `AC Power:` gives a dictionary without `.battery`
- [ ] **Step 2:** Run `scripts/test.sh`. Expected: compile failure, `networkWake` not found.
- [ ] **Step 3:** Implement. Track the current section by unindented lines ending in `:`, and read `key value` pairs
  the same way `sleepDisabled` does.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.

### Task 2: Summarise the last sleep from `pmset -g log`

**Files:**
- Create: `Sources/SleepCore/WakeLog.swift`
- Test: `Tests/SleepCoreTests/WakeLogTests.swift`

**Interfaces:**
- Produces:
  - `public struct SleepSummary: Equatable, Sendable { public let start: Date; public let end: Date; public let darkWakes: Int; public let mainReason: String?; public let chargeAtStart: Int?; public let chargeAtEnd: Int? }`
  - `WakeLog.lastSleep(fromPmsetLog: String) -> SleepSummary?`
  - `WakeLog.reason(fromDarkWakeMessage: String) -> String?`
  - `WakeLog.describe(_ summary: SleepSummary) -> String`, the grey menu line

**Rules the tests pin down:**
- Line shape: `^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4}) (.+?)\s*\t(.*)$`. Group 2 is the event type (`Sleep`,
  `DarkWake`, `Wake`, `Wake Requests`, …). Dates are parsed with `yyyy-MM-dd HH:mm:ss Z`, `en_US_POSIX`.
- The last sleep runs from the first `Sleep` line after the second-to-last `Wake` line (or the start of the log) up to
  the last `Wake` line. Only the type `Wake` counts as a full wake, not `DarkWake` or `Wake Requests`.
- `reason`: take the text after `due to ` and before ` Using`, split it on spaces and `/`, drop tokens containing `.`
  or `(`, and return the first token left. `mainReason` is the most common reason across the counted DarkWakes.
- Charge: `Charge:(\d+)%` on the `Sleep` line that starts the window, and on the last line before the final `Wake`.
  The `Wake` line itself is left out, because the charger may already be plugged in by then.
- `describe`: `"Last sleep: woke 1,705 times (wifibt) · 38% → 1%"`. Thousands separator; the charge part is left out if
  either value is nil; `"woke once"` for 1; `"didn't wake"` for 0.

- [ ] **Step 1: Write the failing tests** with a trimmed fixture made of the real lines from 2026-11-06 22:11–22:14 and
  2026-11-07 11:41 (shown above in "Why", from `pmset -g log`), plus one `Wake` line before them:
  - `reasonFromWifiWake`: `reason(fromDarkWakeMessage: "DarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty/ Using BATT (Charge:1%) 16 secs") == "wifibt"`
  - `reasonFromTimedWake`: the `NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance` line gives `"rtc"`
  - `countsDarkWakesInLastSleep`: `darkWakes == 5`, `mainReason == "wifibt"`, `chargeAtStart == 1`,
    `chargeAtEnd == 1`, `start` == 2026-11-06 22:11:47 +0200, `end` == 2026-11-07 11:41:20 +0200
  - `nilWithoutFullWake`: a log with only `Sleep`/`DarkWake` lines gives `nil`
  - `describesSummary`: the three wordings above
- [ ] **Step 2:** Run `scripts/test.sh`. Expected: compile failure.
- [ ] **Step 3:** Implement in `Sources/SleepCore/WakeLog.swift`. Walk the lines once and keep track only of the
  current sleep window. The input is 45,000 lines, so don't build an array of every event.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: all pass.

## Phase 2: Allow the commands without a password

### Task 3: Wider sudoers rule and Real Sleep commands

**Files:**
- Modify: `scripts/setup.sh` (the rule text and its header comment)
- Modify: `Sources/SleepCore/SleepControl.swift`

**Interfaces:**
- Consumes: `PowerSettings.networkWake(fromPmsetCustomOutput:)`, `WakeLog.lastSleep(fromPmsetLog:)`
- Produces (all on `SleepControl`):
  - `static let realSleepOnArguments = ["-b", "powernap", "0", "tcpkeepalive", "0", "womp", "0"]`
  - `static let realSleepOffArguments = ["-b", "powernap", "1", "tcpkeepalive", "1", "womp", "0"]`
  - `public static func batteryNetworkWake() -> NetworkWakeSettings?` (runs `pmset -g custom`; nil without a battery)
  - `public static func realSleepSetupIsDone() -> Bool` (`sudo -n -l` on both argument lists, the same way
    `setupIsDone` works now; rename that one to `lidClosedSetupIsDone()`)
  - `@discardableResult public static func setRealSleep(_ on: Bool) -> CommandResult`
  - `public static func lastSleepSummary() -> SleepSummary?` (slow; callers run it off the main actor)

- [ ] **Step 1:** In `setup.sh`, add the two command lines to the same rule, in exactly the argument order above, and
  keep the `visudo -cf` check.
- [ ] **Step 2:** Implement the `SleepControl` additions. `setRealSleep` decides success by the exit status only.
- [ ] **Step 3:** Run `scripts/test.sh` and `scripts/build.sh`. Expected: both succeed.
- [ ] **Step 4 (user, by hand):** `sudo scripts/setup.sh`, then check that both commands are allowed. Expected: both
  print the command path and exit 0.

```bash
sudo -n -l /usr/bin/pmset -b powernap 0 tcpkeepalive 0 womp 0
```

```bash
sudo -n -l /usr/bin/pmset -b powernap 1 tcpkeepalive 1 womp 0
```

## Phase 3: Menu

### Task 4: "Real Sleep on Battery" item and last-sleep line

**Files:**
- Modify: `Sources/SleepManager/AppDelegate.swift`

**Interfaces:**
- Consumes: everything Task 3 produces.

**Behaviour:**
- New item after Lid Closed Mode: **Real Sleep on Battery**. Checkmark `.on` / `.off` / `.mixed` from
  `RealSleepState`. Clicking it calls `setRealSleep(state != .on)`, so a mixed state switches fully on. Then it reads
  the settings again.
- Subtitle while on: `"Find My can't locate it while asleep"`. While setup is missing: greyed out with
  `"Setup needed: run setup.sh again"`. Hidden when `batteryNetworkWake()` is nil.
- A grey line under it, `WakeLog.describe(summary)`, shown only when a summary is cached.
- The summary is loaded with `Task.detached` at launch and on `NSWorkspace.didWakeNotification`, and stored on the main
  actor. `menuNeedsUpdate` only reads the cached value, and never calls `pmset -g log`.
- `refreshState()` (launch, menu open, the 30 s timer) also reads `batteryNetworkWake()` and `realSleepSetupIsDone()`.
- The menu bar icon doesn't change (D6).

- [ ] **Step 1:** Implement. Copy the existing `lidItem` pattern for the item, its setup state and its error alert.
- [ ] **Step 2:** Run `scripts/build.sh`, then `scripts/install.sh`. Expected: the app restarts in the menu bar.
- [ ] **Step 3 (manual checks):**
  - Toggle on, then `pmset -g custom` shows battery `powernap 0 tcpkeepalive 0 womp 0`. Toggle off shows `1 1 0`.
  - `sudo pmset -b powernap 1`, then reopen the menu. Expected: mixed checkmark.
  - With the old rule (`sudo scripts/setup.sh uninstall`, then reinstall the old rule from git): Lid Closed Mode
    works, Real Sleep shows "Setup needed".
  - The menu opens without delay right after launch, while the wake log is still loading.
  - After a sleep and wake, the grey line updates.

## Phase 4: Docs

### Task 5: README and spec

**Files:**
- Modify: `README.md` (menu table row, the setup section's list of allowed commands, the Find My trade-off, and how to
  undo by hand: `sudo pmset -b powernap 1 tcpkeepalive 1 womp 0`)
- Modify: `docs/superpowers/specs/2026-10-30-sleep-manager-design.md` (add D1–D6 to "Decisions made with the user",
  and replace the "only the two exact `pmset disablesleep` commands" anti-goal with "only the exact commands listed in
  `setup.sh`")

- [ ] **Step 1:** Edit both files.

## Phase 5: Two sleep tests on this Mac

Two runs, each on battery. The user decides how long the Mac sleeps and says when to check. Claude then reads the log
for that sleep only:

```bash
pmset -g log | grep -E "^\S+ \S+ \S+ (Sleep|DarkWake|Wake) " | tail -400
```

Claude also reads `pmset -g custom` and the menu's "Last sleep" line, and reports the DarkWake count, the reasons
(`wifibt`, `rtc`, …) and the battery drop.

### Test 1: feature on

- [x] The user switches on **Real Sleep on Battery**. Claude checks `pmset -g custom`: battery shows `powernap 0`,
  `tcpkeepalive 0`, `womp 0`. (2026-11-07: done; the rule was confirmed with `sudo -k` first.)
- [ ] The user leaves the Mac asleep on battery for a while, then reports back.
- [ ] Claude checks the log. **Pass:** few or no DarkWakes, with no `wifibt` ones. Sleep lines no longer say
  `TCPKeepAlive=active`. The occasional timed `rtc` wake is fine.

### Test 2: defaults restored

- [ ] The user switches **Real Sleep on Battery** off. Claude checks `pmset -g custom`: battery is back to
  `powernap 1`, `tcpkeepalive 1`, `womp 0`.
- [ ] The user leaves the Mac asleep on battery for about as long as in Test 1, then reports back.
- [ ] Claude checks the log. **Pass:** DarkWakes are back (`wifibt`, about once a minute, as on 2026-11-06), which
  shows that the difference in Test 1 came from the feature.

**Done when (whole feature):** Test 1 shows a few or no DarkWakes, Test 2 shows them coming back, and the menu's "Last
sleep" line matches the log both times. If Test 1 still shows `wifibt` wakes, stop and look at Bluetooth wake before
changing anything else.
