# Display popout: tabs + per-monitor scale

Files: `.config/quickshell/bar/Bar.qml` (display popout, ~line 1235 `displayPopout`), `.config/quickshell/common/Sys.qml`, `.config/hypr/scripts/monitor-layout.sh`.
No new bar cell, no new files. Rules: reuse what is there (StepBtn, ToggleRow, ValueSlider, clanker tab chips at `Bar.qml:~3418`).

## Why
- popout is packed: brightness, night light, idle ladder, duo toggles, all in one column
- no way to change monitor scale from the bar; omarchy has it (presets 1/1.25/1.6/2/3/4 per focused monitor)
- current profile `HDMI-A-1,eDP-1` has no saved layout in `~/.local/state/hypr/layouts/`, so a hotplug replay falls to the `*` case and resets eDP-1 to scale 1

## 1. monitor-layout.sh: `scale` subcommand
File: `.config/hypr/scripts/monitor-layout.sh`.
- `monitor-layout.sh scale <output> <scale>`
- read that output's current mode/pos/transform from `$MONS` with jq, call the existing `apply` with the new scale
- then `exec "$0" save` so the profile file exists and hotplug replays it
- **must re-exec, not fall through**: `$MONS` is captured once at the top, so saving in the same process would write the pre-change scale
- `sleep 0.5` before the save: the modeset is not visible to `hyprctl monitors` the instant `hyprctl eval` returns
- BUILT & TESTED. Positions need no recompute: Hyprland reflows adjacent outputs itself. Scaling eDP-1 1.5 -> 2 moved HDMI-A-1 from `1920x0` to `1440x0` with no gap or overlap.

## 2. Sys.qml: monitors list + setScale
File: `.config/quickshell/common/Sys.qml`, next to `duoStateProbe` (~line 155).
- `property var monitors: []` of `{ name, desc, scale }`
- `monProbe`: `hyprctl -j monitors | jq -c '[.[]|{name, desc:.description, scale}]'`, one line, StdioCollector
- fire it from `poll()` (panel open) and from a one-shot 1.2s readback timer restarted by `setScale`. **No heartbeat**: the existing 2s `panelOpen` timer is gated on `isDuo` so it never fires on the other hosts, and a periodic array reassign resets the Repeater and destroys the pill's hit area mid-click (same trap the `backlights` comment documents).
- guard: stringify the read, skip the assign when identical to the last one
- `setScale(name, s)`: execs the script and restarts the readback. **Does not touch `monitors`** — the row echoes the click locally (`ScaleRow.shown`), so the array changes only when the probe brings back something new. Mutating it here would rebuild the Repeater and delete the pill's MouseArea, or the row holding keyboard focus, mid-gesture.
- probe re-reads after; if Hyprland coerced the scale the pill moves to the real value

## 3. Bar.qml: tabs
File: `.config/quickshell/bar/Bar.qml`, display popout.
- `property string tab: "screen"` on the `dispPopout` QtObject. Lives while the bar runs, back to `screen` on restart.
- tab chip row at the top of `dispCol`: clanker chips styling (`Bar.qml:~3418`), model `["screen", "idle", "monitors"]`. **One tab stop for the whole row, h/l switches tabs** — three separate stops would cost three j/k presses before reaching content, and `AttachedPanel.onKeyNavChanged` lands focus on the first item when the popout is keyboard-opened.
- three inner `Column`s under the chips, `visible: dispPopout.tab === "..."`. Invisible items drop out of the focus chain, so j/k nav only walks the open tab.
- move existing rows, no rewrites:
  - `screen`: brightness Repeater, lock together, night light toggle, temperature slider
  - `idle`: keep awake, lock / screen off / suspend IdleRows
  - `monitors`: new scale rows (4), then Duo `sub screen` + `auto-rotate`
- ValueSlider / StepBtn / IdleRow components stay declared once at `dispCol` level (inline components are file-scoped anyway)
- `implicitHeight` is already `dispCol.implicitHeight + 28`, so it follows the tab

## 4. Bar.qml: scale rows
- `component ScaleRow: Item`, one per `Sys.monitors` via Repeater
- left: `modelData.name` (11px, Theme.text). desc is too long for 280px, skip it
- right: Row of pills for `[1, 1.25, 1.5, 1.6, 2, 3]`, current one `Theme.accent` bg + `Theme.accentText`, others `Theme.dim` text, hover `Theme.track` (same look as StepBtn)
- click pill: `Sys.setScale(modelData.name, v)`
- keys: row is one tab stop, arrows and h/l move to prev/next preset and commit
- `h`/`l` did not actually work anywhere before this, despite three comments saying so: rows only bound `Keys.onLeftPressed`/`onRightPressed`, which are arrows, and `AttachedPanel` handled only j/k/arrows/Esc. Fixed once at the shared dispatch: rows opt in with `hstep(dir)` (ValueSlider, IdleRow, ScaleRow, the tab row) and `AttachedPanel` routes H/L to the focused item's `hstep`.
- 1.6 is in the list because Hyprland coerces to it: 1.5 on the 2560-wide HDMI gives a non-integer logical width and comes back as 1.6. Without the pill a legal click would leave nothing selected. 4 dropped.

## Check
- open popout, tabs switch, j/k stays inside the visible tab
- `monitors` tab shows eDP-1 at 1.5 and HDMI-A-1 at 1, click 2 on eDP-1: UI scales live, `~/.local/state/hypr/layouts/HDMI-A-1,eDP-1` appears with scale 2
- click 1.5 back, file updates
- unplug/replug HDMI: layout replays with the saved scale
- Duo toggles still work on the `monitors` tab

## Built
All items done and verified on binstar (eDP-1 + HDMI-A-1).
- `monitor-layout.sh scale <out> <scale>` applies live and re-saves the profile; the `HDMI-A-1,eDP-1` profile now exists, so a hotplug no longer resets eDP-1 to scale 1
- all three tabs render and switch; live scales show correctly (eDP-1 1.5, HDMI-A-1 1)
- displays restored to their starting scales after testing

### Measured
- compositor reports a new scale 0.14s after the write, so the 1.2s readback timer is safe
- `scale HDMI-A-1 1.5` came back as 1.60 and the saved profile recorded 1.60, not the requested 1.5 — the re-exec save persists what the compositor did, not what was asked
- saved profiles re-checked against live state afterwards; both match, displays left at their starting scales
