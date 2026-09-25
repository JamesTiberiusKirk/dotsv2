# Display state: stop the fighting

Supersedes `plan-hostd.md` stages 1-4. No new daemon. `hostd` stays shelved
until something still stomps display state after this.

Revised 2026-09-25 after an adversarial review that killed two of the original
seven changes. See **Rejected** at the bottom for what was dropped and why.

## Root cause

**Desired state is computed from current state.**

- `monitor-layout.sh:16,20` keys the layout profile off `hyprctl monitors -j`.
- That lists **enabled** outputs only (disabled and mirrored are omitted;
  dpms-off ones are still listed).
- So disabling a screen *changes which profile applies*.

Evidence, from `~/.local/state/hypr/layouts/`:

```
HDMI-A-1,eDP-1,eDP-2  →  eDP-1 scale 2,    HDMI at 1440x0
HDMI-A-1,eDP-1        →  eDP-1 scale 1.50, HDMI at 1920x0
eDP-1,eDP-2           →  eDP-1 scale 1.5
eDP-1                 →  eDP-1 scale 2
```

Same hardware. Different geometry. Turning the sub screen off rescales the main
screen and moves the external.

It is a profile flip, not an infinite loop — today it converges in one or two
hops, because `save` never records a disabled output so a dark eDP-2 is never
replayed. The visible symptom is the rescale/reposition on each hop, plus
whatever raced with it.

## Second cause: reload replays config rules, drops runtime ones

- `hosts/*.lua` carry `hl.monitor` lines.
- `hyprctl reload` rebuilds the rule list from config and **drops** runtime
  `hyprctl eval hl.monitor` rules. Three callers: `load-plugins.sh:9`,
  `theme-apply:231`, `binds.lua:175`.
- `duo`'s `reassert()` exists partly to undo that.
- `.scripts/powersave:47` reverts its refresh-rate change *with* `hyprctl reload`.

## Third cause: nobody reads the kernel

- Zero reads of `/sys/class/drm/card*-*/{status,enabled}` anywhere in the repo.
- 2026-09-25: `HDMI-A-1` `disconnected` + `enabled` held a CRTC; every eDP-1
  modeset EINVAL'd. Looked like a dead panel. Restarting Hyprland fixed it.

## Measured 2026-09-25 — the actual bounce, found by elimination

The sub-screen flicker is a two-process loop, and neither end is
`monitor-layout.sh`:

1. `duo` disables eDP-2 (dock rule or `duo screen off`)
2. Hyprland emits `monitorremoved`
3. `monitor-watch.sh` react() → `wallpaper.sh --current` → **`awww img`
   re-enables eDP-2**
4. `monitoradded` → react() again; `duo`'s 5s `reassert()` turns it off again
5. forever

Isolation, each step verified on the live machine:

- watcher `SIGSTOP`ped, `duo` running, `duo screen off` → panel stayed off 8s.
  Clean. So `duo` alone does not oscillate.
- watcher stopped, panel off, ran `monitor-layout.sh` → **stayed off**. The
  re-keyed script with the intent skip is correct.
- watcher stopped, panel off, ran `wallpaper.sh --current` → **panel back on.**

`wallpaper.sh` contains no monitor call of its own (only `hyprctl cursorpos`,
read-only). The revival comes from its tail:

- `wallpaper.sh:83-85` — the active theme is literally named `wallpaper`, so every
  repaint regenerates it and re-runs `theme-apply wallpaper`
- `theme-apply:231` — `hyprctl reload`
- reload replays `binstar.lua:31-34`, whose eDP-2 rule branches on `docked()`
  **and nothing else**. Keyboard detached → the enabled rule → panel on.

So `duo screen off` with the keyboard detached is guaranteed to be undone by any
reload, because the config's idea of eDP-2's power ignores the manual override
entirely. That is exactly the "keyboard off *and* sub screen off just would not
stay" complaint.

Code path is unambiguous; a reload-triggered revival has not yet been caught in
`hyprctl rollinglog` directly (the log window had already rolled past it).

Also found: a `duo watch` from a Hyprland session that died on Sep 22 was still
running on Sep 25, sharing the same `screen-override` file and log with the live
one and firing `reassert` every 5s. The missing single-instance guard from
`plan-hostd.md` is real and was live. Killed.

Two further corrections to earlier assumptions:

- A `hl.monitor` rule that omits `disabled` **does** revive a disabled output.
  `duo/hypr.go:13` claims the opposite; it is wrong on this Hyprland. So the only
  way not to touch an output's power is to emit no rule for it at all.
- Skipping on the panel's *current* power races the modeset (the watcher's 0.5s
  debounce expires first). Skip on duo's *intent* — override file plus the USB
  dock glob — which cannot race.

### Change 0 — DONE, verified 2026-09-25

`binstar.lua` must read duo's full intent, not just `docked()`: the manual
override file too, same predicate as `monitor-layout.sh`'s `edp2_wanted` and
duo's `reassert()`. One file, and it kills this loop at the source.

Rejected on the way here: gating `monitor-watch.sh`'s wallpaper repaint on
`monitoradded`. `react()` is one debounced callback with no memory of which event
armed it, and the loop re-closes through the next add anyway — it would slow the
flicker, not stop it. The power rule being wrong on reload is the real defect,
and fixing it is already change 3.

## Changes

Status: 0 done. 1, 2, 4, 5 done (Stage A). 3, 6, 7, 8 open.

Acceptance test that now passes, and failed before: keyboard detached,
`duo screen off`, every watcher running — eDP-2 stayed off 12s with **zero**
`reassert` lines in duo's log. Before, the panel flipped back on at 3s, 7s and
11s and duo re-issued the disable every 5s forever.

1. **Re-key profiles on connected, not enabled** — `monitor-layout.sh`
   - key from `/sys/class/drm/card1-*/status == connected`
   - glob is per-GPU on purpose: a multi-GPU host (legion) would otherwise pull
     in connectors Hyprland isn't driving and never match a profile
   - on/off becomes a state *inside* a profile, never a profile switch
   - a ghost (`disconnected` + `enabled`) stops counting as present

2. **`apply()` never emits `disabled=` for eDP-2** — `monitor-layout.sh:35`
   - a rule without `disabled` leaves power state alone (`duo/hypr.go:13-15`)
   - **this is what keeps `duo` the sole owner of eDP-2's power.** Without it,
     change 1 makes layout.sh replay a stale dock state and fight `duo`
   - supersedes the `:31` override-skip hack, which only covered manual-off

3. **`hosts/*.lua` emit rules from the saved profile file**
   - not "strip all `hl.monitor`" — that makes reload auto-relayout everything
     (`preferred`/`auto`/`disabled=false`), so eDP-2 wakes while docked and
     eDP-1 jumps to DPI auto-scale, then gets corrected a beat later: two
     modesets per panel on every theme toggle, plus a boot race
   - instead, lua reads `~/.local/state/hypr/layouts/<profile>` and emits the
     same geometry layout.sh applies live. `base.lua:21-44` already does this
     file-reading pattern for `.layout`
   - `binstar.lua` additionally reads `docked()` + `~/.local/state/duo/screen-override`
     to get eDP-2's power state right at reload time
   - reload becomes idempotent. No `configreloaded` listener, no window, no race.

4. **`apply()` builds one eval, not one per output** — `monitor-layout.sh:24-36`
   - `duo/rotate.go:56-58` already learnt this: separate evals leave a transient
     overlap between outputs

5. **`flock` on `$STORE`** — `monitor-layout.sh`
   - `monitor-watch.sh`, `idle:50` on-resume, `base.lua:330`, `Sys.qml:214`
     scale and `Menu.qml:96-97` save can all interleave. One line.

6. **Delete `reassert()`** — `duo/watch.go:118-132`
   - **only after 2 and 3 land.** It covers more than reload: `duo layout
     stacked|mirror|mirror-flip` enables eDP-2 while docked without setting an
     override (`duo/hypr.go:88-114`), the boot race, nwg-displays
   - once reload can't flip eDP-2 and layout.sh can't either, what's left is
     `duo layout` setting no override — fix that directly instead of polling

7. **`powersave` reuses the profile lines with refresh swapped** — `.scripts/powersave`
   - `:21-25` currently regenerates rules from `hyprctl monitors -j` and omits
     `transform`, which un-rotates a rotated panel
   - `:47` reverts via `monitor-layout.sh`, not `hyprctl reload`

8. **Kernel-truth check** — `monitor-layout.sh` (~15 lines)
   - after apply: compare intent against `/sys/class/drm/card1-*/enabled`
   - `disconnected` + `enabled` → `notify-send` "ghost <out>, restart Hyprland"
   - one notify, logged, no retry loop. Notify-only — see Out of scope.

## Kept

- `monitor-layout.sh` — geometry: apply / save / replay / kernel check
- `monitor-watch.sh` — events: hotplug → calls the above
- `duo` — dock, screen power + override, rotate, brightness, keyboard

Untouched: `idle` (dpms), `nightlight` (gamma), `kvm-toggle.sh` (deathstar),
`wallpaper.sh`.

## Must keep working

- `duo screen on|off|toggle` with the override latch
- `duo autorotate on|off`
- keyboard dock/undock driving eDP-2
- all of the above with an external screen attached

## Rejected

- **Per-output `enabled` field in the profile file.** Dock state is dynamic, a
  saved field is a snapshot. Saved while undocked then docked: layout.sh replays
  `enabled` with `disabled=false`, eDP-2 wakes under the keyboard, `duo`'s dock
  state never changed so nothing corrects it. Change 2 instead.
- **Stripping all `hl.monitor` from `hosts/*.lua`.** See change 3.

## Unresolved

- **`display/arrange` is dead.** `Menu.qml:96` launches nwg-displays, which
  writes `monitors.conf` and calls `hyprctl reload` — the lua config never
  sources that file, and `hyprctl keyword` is rejected under the lua parser. So
  arranging does nothing and `save` snapshots an unchanged layout. Any migration
  step that says "arrange each setup once, then save" has no working front-end.
  The live editors are `duo layout` / `scale` in the display popout.
- **`duo layout` and `duo rotate` are geometry writers too**
  (`hypr.go:21-25`, `rotate.go:62-65`) and hardcode scale 1.5 / fixed positions,
  while the HDMI profile has eDP at scale 2. Replaying a profile after a rotate
  resets transform to the file's value. The ownership split isn't clean until
  these read the profile or hand geometry to layout.sh.

## Out of scope

- **Sound.** CS35L41 right amp dead after resume. Root-side, needs a service
  under `system/`, unrelated to display. Parked.
- **Freeing a ghost CRTC without restarting Hyprland — closed, not possible from
  userspace.** Tested 2026-09-25 with a live ghost: root
  `echo detect > /sys/class/drm/card1-HDMI-A-1/status` left it `disconnected` +
  `enabled`. The CRTC is held by Hyprland's DRM master lease; re-probing the
  connector cannot take it back. Only the compositor exiting releases it.
- Fixing aquamarine. Report upstream.
