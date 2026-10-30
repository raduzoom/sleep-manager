# Design brief: Sleep Manager (macOS menu bar app)

Paste everything below this line into Claude Design.

---

## What this is

Sleep Manager is a tiny macOS menu bar utility for one person. It puts two "don't sleep" modes one click away, so the
Mac can keep working on long tasks, sometimes with the lid closed. It has no Dock icon and no main window: the menu bar
icon and its dropdown are the whole app.

The single most important job of the design: **when Lid closed mode is on, the menu bar icon must be noticeably
reddish.** That red icon is the only reminder that the Mac won't sleep. If it's forgotten, the battery drains and the
laptop runs hot in a bag.

The interface should be simple and feel native, like Apple's own Wi-Fi or Bluetooth menu extras.

## Platform constraints

- macOS 26 menu bar. The icon sits among system icons and must read at menu bar size (artwork about 16–18 pt tall on a
  22 pt high bar) on both light and dark menu bars and over colorful wallpapers.
- The dropdown is a **standard macOS menu**, not a custom panel: system font, standard row height, checkmarks, separators,
  submenus, disabled (grey) informational rows, optional SF Symbols beside items. Please don't use switches, sliders,
  colored backgrounds or custom layouts inside the menu. The mockups must be buildable as a native menu.

## The modes

| Mode | What it does | Command behind it |
|---|---|---|
| Keep awake | Mac and screen stay awake while the lid is open | `caffeinate -d` |
| Lid closed | Mac keeps working even with the lid shut; normal sleep is off until switched back | `pmset -a disablesleep 1` / `0` |

The two modes are independent: either, both, or neither can be on.

## Icon: three states

Design one icon concept in three states:

1. **Off**: normal sleep. Monochrome and quiet, like other system icons, and adapts to light/dark menu bars.
2. **Keep awake on**: visibly "active" but calm. Still monochrome (for example a filled vs. outline variant, or an
   added mark). It should not look like a warning.
3. **Lid closed on**: **reddish**. This state is in color and stays red on both light and dark menu bars. It should
   draw the eye without looking like an error or a crash. When both modes are on, this state is shown.

Please propose 2–3 icon concepts first, each shown in all three states on light and dark bars, then refine the chosen
one. Concept directions are open; a moon, a coffee cup, an open/closed laptop, or something more abstract are all fine,
as long as the three states are easy to tell apart at a glance.

## Dropdown menu

Items in order, with suggested wording (feel free to improve it):

```
Sleeping normally                          ← grey status row (not clickable)
─────────────
Keep Awake                                 ← checkmark when on
Lid Closed Mode                            ← checkmark when on
─────────────
Turn Screen Off Now
What's Keeping It Awake                  ▸ ← submenu
─────────────
Quit Sleep Manager
```

The status row changes with the state:

| State | Status row |
|---|---|
| Neither mode on | Sleeping normally |
| Keep awake on | Keeping awake (screen on) |
| Lid closed on | Lid closed mode on: Mac won't sleep |
| Both on | Lid closed mode on: Mac won't sleep |

Two special cases:

- **Turn Screen Off Now when neither mode is on.** The screen goes dark, but the Mac may then sleep normally. Show a
  short hint for this case, for example a second grey line or a subtitle "Mac may sleep".
- **Setup needed.** Lid closed mode needs a one-time admin setup. If it's missing, Lid Closed Mode is disabled and a row
  explains it, for example "Setup needed: run setup.sh once". Design how that row looks.

## "What's Keeping It Awake" submenu

A read-only list of what is currently preventing sleep, built from `pmset -g assertions`. Each row is one process: its
name, what it prevents, and for how long. Below is a real sample from the user's Mac, cleaned up:

| Process | Prevents | For |
|---|---|---|
| caffeinate | Display sleep | 29 h 28 min |
| Claude | Idle system sleep | 3 h 33 min |
| powerd | System sleep while display is on | 5 h 32 min |
| WindowServer | (user is active) | a few seconds |

Design how these rows read in a native submenu. Ideas: the process name as the main text and the rest grey, an SF
Symbol per type (display vs. system), and a grey "Nothing is keeping it awake" row when the list is empty. It's fine to
suggest hiding noisy system entries such as WindowServer's "user is active".

## What to send back

1. **Icon assets**: the chosen concept as vector files, **one SVG (or PDF) per state**: `icon-off`, `icon-keep-awake`,
   `icon-lid-closed`. The off and keep-awake icons should be single-color (black on transparent) so macOS can tint them;
   the lid-closed icon keeps its red. State the exact red you used (hex).
2. **Mockups (PNG)** of the open menu in each state, on light and dark menu bars:
   - neither mode on
   - Keep awake on
   - Lid closed on
   - both on
   - setup needed
   - the "What's Keeping It Awake" submenu open (with the sample data above, and the empty state)
3. **Final wording** for every menu row, as a plain list.
