# plan: brightness offsets — locked monitors that keep their differences

Status: designed with darthvader 2026-10-01, not started. Binstar only (duo).
Implementer: read this whole file, then `duo/brightness.go`, `duo/extbright.go`,
`duo/publish.go`, `.config/quickshell/common/Sys.qml`,
`.config/quickshell/common/ValueSlider.qml`,
`.config/quickshell/bar/popouts/DisplayPopout.qml` before editing.

## issues to solve

- Locked ("lock together") forces every monitor to the SAME value.
- Wanted: locked monitors keep a fixed offset from each other (e.g. MSI 20
  dimmer than the laptop), and still move together on keys and the main slider.
- The panel has no way to see or set per-monitor values while locked.

## behaviour (agreed — do not change)

- Locked = one group. Each monitor has a fixed offset. Keys and the main slider
  move the group; offsets never change from that.
- Block stop: going down stops as soon as ANY monitor hits its minimum (1%);
  going up stops as soon as ANY hits 100%. Offsets are never squashed.
  - Clamp to the edge, don't refuse the step: e.g. dimmest at 3, step -5 →
    group moves -2 so the dimmest lands on exactly 1.
- Main slider shows the BRIGHTEST participating monitor's value.
  - Its `minValue` = 1 + spread (spread = brightest − dimmest), so the knob
    physically cannot go below the block stop.
- Accordion: a chevron on the main slider expands one slider per monitor.
  Dragging one changes only that monitor's offset (its value moves, nobody
  else's does).
- Unlocked stays exactly as today: independent sliders, keys follow the
  focused monitor. Do not touch the unlocked path.
- Offsets persist across reboots, keyed by monitor identity (see storage).
- Unplugged monitor keeps its offset; reapplied when it returns.
- Never-seen monitor joins with offset 0.

## decisions taken by the planner (not discussed — flag to darthvader if wrong)

- Re-locking (unlocked → locked) re-applies the SAVED offsets relative to the
  top panel's current value, block-clamped. Unlocked tweaks are temporary and
  do not overwrite offsets. (Today re-lock snaps everything to eDP-1.)
- Participants = monitors that are actually lit:
  - top panel (`intel_backlight`) always
  - bottom panel only while `/sys/class/drm/card1-eDP-2/enabled` = `enabled`
    (a dark panel under the keyboard must not block the group's range)
  - externals in `extConnectors()`
- Reference for the current level = the top panel (always present, sysfs is
  instant and reliable). No stored level: level = pct(top) − offset(top).

## model

```
value_i = L + off_i                      for each participant i
lo = 1   - min(off_i)                    lowest legal L
hi = 100 - max(off_i)                    highest legal L
L  = clamp(L, lo, hi)
main slider value = L + max(off_i)
```

- Group step (keys): `delta = bstep(mainValue, up) - mainValue` (reuse the
  existing `bstep` feel), `L = clamp(L + delta, lo, hi)`.
- Group set (main slider to M): `L = clamp(M - max(off_i), lo, hi)`.
- Member set (accordion row k to v, v clamped 1..100):
  `off_k = v - L`, save, apply only monitor k.
- If lo > hi (offsets wider than 99 apart — only possible via hand-edited
  file): clamp offsets so spread ≤ 99, log it.

## storage — `~/.local/state/duo/brightness-offsets`

- One line per monitor: `<key> <offset>` (int, may be negative).
- Keys:
  - `top`, `bottom` for the internal panels
  - externals: the EDID identity from `$XDG_RUNTIME_DIR/hypr-monitors`
    (written by `.config/hypr/monitors.lua`, lines `<connector> <id>`, e.g.
    `DP-1 CND-MPG322UX24`). Fallback when the map is missing or has no entry:
    the connector name.
- Read/write via `statePath("brightness-offsets")` (`duo/state.go`), same
  helpers as `brightness-sync`.
- Missing file or key = offset 0.

## duo changes (`duo/`)

New file `duo/group.go`:
- `type member struct { key, target string; pct int }`
  - `target` is what `apply`/`extSetPct` take: `top`, `bottom`, or a connector.
- `participants() []member` — per the decision above; pct from `pctOf`
  (internals) and `extSrv.values()`/`extConnectors()` (externals; in the CLI
  process there is no `extSrv`, so read the externals' last values from the
  daemon's state file `runtimePath("state")` `ext` lines).
- `loadOffsets() map[string]int`, `saveOffsets(map[string]int)`.
- PURE math, no I/O, so it is testable:
  `groupLevel(offs []int, L, delta int, set bool) int` (or similar) returning
  the clamped L; plus `bounds(offs []int) (lo, hi int)`.
- `applyGroup(L int)` — writes every participant `L+off`: internals via
  `apply(pct, "top"|"bottom")`, externals via `extSetPct(conn, pct)`.
- `groupMain() (main, min int)` for the state file.

`duo/brightness.go`, locked path only (`brightnessSync()` true):
- `up`/`down` with no target or target `all` → group step.
- `set N all` → group set (main slider).
- `set N <target>` with an explicit target other than `all` → member set
  (offset edit). Today an explicit target "loses to the lock" — replace that
  with the member-set behaviour. Map slider names to targets as
  `Sys.setBrightness` already does (`card1-eDP-2-backlight` → `bottom`,
  `intel_backlight` → `top`, connector stays connector).
- `sync on` → re-apply saved offsets (decision above) instead of
  `applyAll(top pct)`.
- Keep the OSD call for keys as is.
- Unlocked path: unchanged.

`duo/publish.go`:
- Add `group <main> <min>` line when locked (main = brightest participant,
  min = dimmest). Sys.qml uses it for the main slider value and `minValue`.

Test: `duo/group_test.go`, table-driven, for the pure functions:
- block stop down (dimmest lands exactly on 1, others keep offsets)
- block stop up (brightest lands exactly on 100)
- group set below/above range clamps
- member set changes only that offset
- zero participants / one participant
Run with `cd duo && go test ./...`.

## quickshell changes

`common/ValueSlider.qml` — accordion as a base feature (darthvader asked for it
in the base widget):
- `property bool expandable: false`, `property bool expanded: false`.
- When `expandable`, show a chevron via the existing `trailIcon`
  (`chevron-up`/`chevron-down`) and toggle `expanded` on `trailPressed`.
  Existing pattern to copy: `bar/popouts/AudioPopout.qml` `podsOpen`
  (lines ~24, 99-100, 139).
- The slider does not own the expanded content; the caller puts a Column
  under it with `visible: thatSlider.expanded`. Keep ValueSlider 30px tall.

`common/Sys.qml`:
- New `property var brightnessPct: ({})` — name → pct, reassigned on EVERY
  state-file update (`applyDuoState`), panel open or not.
- New `property int groupMain`, `property int groupMin` from the `group` line.
- Rows: keep `brightnessRows` (the Repeater model) reassigned ONLY when the
  set of names changes (existing rule — reassigning destroys the slider mid
  drag). Sliders read their value from `Sys.brightnessPct[name]`, not from
  `modelData.pct`, so values update live without rebuilding the Repeater.
  ValueSlider already ignores `value` changes while `held`.
- Locked: `brightnessRows` = the single main row (`name: "all"`), plus a new
  `memberRows` list (one per participant, same shape as the unlocked rows) for
  the accordion.
- `setBrightness(name, v)` already routes `all`/connector/`top`/`bottom`
  through duo — no change needed beyond what duo now does with an explicit
  target while locked.

`bar/popouts/DisplayPopout.qml` (brightness block, ~lines 125-145):
- Locked: main ValueSlider with `expandable: true`, `value: Sys.groupMain`,
  `minValue: 1 + (Sys.groupMain - Sys.groupMin)`; under it a Column
  `visible: main.expanded` with a Repeater over `Sys.memberRows`, each a
  ValueSlider (`minValue: 1`) whose commit is `Sys.setBrightness(name, v)`.
- Unlocked: unchanged.
- Collapse the accordion when the popout closes (like `podsOpen`).

## do not

- Do not run ddcutil from quickshell or the CLI for reads; the daemon owns the
  i2c bus (`duo brightness refresh` queues a re-read).
- Do not reassign Repeater models on every state update (see Sys.qml comments
  around `applyDuoState`).
- Do not change monitor rules, hyprland config, or the unlocked behaviour.
- No git writes. darthvader commits.

## deploy + verify (binstar)

- `cd duo && go test ./... && go install .`
- Restart `duo watch` and `qs` with the LIVE session env — see memory note
  `restart-daemons-live-session-env` (take env from a child of the live
  Hyprland pid; kill by `pgrep -x` PIDs, never `pkill -f` a pattern in your own
  command line).
- Checks:
  - locked, set MSI accordion row 20 below the laptop → keys move all, gap
    stays 20
  - keys down until the dimmest hits 1 → further presses do nothing, gap kept
  - main slider can't be dragged below 1 + spread
  - unplug MSI, move group, replug → MSI returns at its offset
  - unlock → old behaviour; re-lock → saved offsets come back
  - slider drag never jumps or rebuilds while the panel is open
