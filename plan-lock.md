# plan: quickshell lockscreen + howdy face unlock

Replace hyprlock with an in-shell `WlSessionLock` so face unlock (howdy) runs
without needing an enter press.

## why not hyprlock

Claim: hyprlock only starts PAM on enter, and an empty enter reads as a wrong
password. Not re-litigated — decision is to move to quickshell. hyprlock stays
installed as the fallback until the new lock is proven.

## verified before planning

- IR cam is `/dev/video2`, `GREY 640x360 @ 15fps`, face visible in a test frame
  captured as the user with no sudo. Camera access is not a blocker.
- Test frame mean brightness ~13%. IR emitter is likely off. Unknown whether
  matching holds in a dark room.
- quickshell 0.3.1 ships `Quickshell.Services.Pam.PamContext`
  (`config`, `start()`, `respond()`, `responseRequired`, `completed(result)`)
  and `Quickshell.Wayland.WlSessionLock` / `WlSessionLockSurface`.
- `IpcHandler` is already the established trigger pattern in this shell
  (`launcher/Launcher.qml`, `osd/Osd.qml`, `wallpaper/Picker.qml`).

`responseRequired` is the piece that makes this work: howdy never asks for a
prompt, so the lock can show "looking for your face" and `respond()` only when
PAM actually asks for the password.

## status

- **package**: `howdy` 2.6.1 (AUR) is useless — ships no PAM module at all
  (`pacman -Ql howdy | grep -c '\.so'` = 0). Replaced with `howdy-next` 3.4.2.
- **python-dlib** (howdy 2.6 dep) fails to build: its PKGBUILD hardcodes
  `_build_cuda=1` and this box is Intel Arc. Moot now — `howdy-next` is a
  cmake build with no dlib dep.
- **phase 1 done**: enrolled, `sudo` wired with
  `auth sufficient pam_howdy.so workaround=native`, "Face matched user
  darthvader". **Then reverted** — see below.
- **phase 2 answered by design**: `howdy-next` ships setuid
  `/usr/lib/howdy/howdy-auth-helper`, documented in `pam_howdy(8)` as existing
  for "unprivileged lock screens". It makes temporary root-controlled copies
  of the config and model. Still worth verifying once in a real user-run
  lockscreen before writing QML.
- **camera**: `device_path` (bare key, not `video.device_path`) set to
  `/dev/v4l/by-id/usb-Shinetech_USB2.0_FHD_UVC_WebCam_200901010001-video-index0`
  → `/dev/video2`. Used by-id because a Dell WB3023 webcam turned up on
  `video4`/`video5` mid-session; the numbering does move on this box.
- IR emitter not needed so far. Matching worked at ambient brightness.

## howdy is not going on sudo

Face proves **presence**, not **consent**. With howdy on `sudo`, any process
running as the user — an agent, a script, anything — gets root by asking,
silently, for as long as the user's face is visible to the camera. No config
option prevents this: `abort_if_ssh` only covers SSH sessions,
`abort_if_lid_closed` only covers a shut lid, `detection_notice` only prints
to a terminal the caller already controls.

The lockscreen is different and is the right place for it: "is the owner
physically here?" is exactly the question a lockscreen asks.

## phases

Each phase is independently testable. Stop after any of them.

### 1. howdy, sudo only

- install `howdy` (AUR, 40 votes), point its config at `/dev/video2`
- enroll face as root
- wire `sudo` PAM only, `sufficient` ABOVE the password line
- test: `sudo -k; sudo true` in a terminal that already has a working shell
- **decides whether the rest is worth building.** If matching is flaky at this
  IR brightness, stop here; `linux-enable-ir-emitter` is the next lever.

### 2. does howdy work unprivileged

- `pamtester` as the user (not root) against a test PAM service
- root-only model dir under `/usr/lib/security/howdy` would fail here
- **this failure is not fixed by changing lockscreens.** quickshell's lock runs
  as the user exactly like hyprlock does.
- if it fails: fix perms or use a howdy build with a privileged helper, before
  writing any QML

### 3. the lock itself

New `/etc/pam.d/quickshell-lock`:

```
auth    sufficient   pam_howdy.so
auth    include      login
```

Order matters. `sufficient` above the include means howdy-success
short-circuits and howdy-failure falls through to the password. Reversed is a
lockout.

**The lock runs as its own quickshell instance**, not inside the bar's shell.
See risks: under ext-session-lock a crash in the shell process while locked
strands the session, and today that process also runs the bar, launcher,
notifications and `BatteryGuard`. A dedicated instance keeps the blast radius
at hyprlock's size. Cost: one extra process and a second config root. It can
still `import "../common"` for `Theme.qml`, so no theme duplication.

New `.config/quickshell/lock/shell.qml` (its own root, run as `qs -c lock`):

- `WlSessionLock { locked: true }` + a `WlSessionLockSurface` per screen
- `PamContext { config: "quickshell-lock" }`, `start()` on lock
- `completed(result)` success -> `unlock()` then quit
- `responseRequired` -> show the password field, `respond(text)`
- failure -> message, restart the context
- `secure` is readonly — a status flag, not a gate. Render the surface opaque
  from frame one; do not wait on it.

Trigger: `lock_cmd` launches `qs -c lock` directly. No IpcHandler — the lock
process is the thing being started, so there is nothing to message. (The
`IpcHandler` pattern at `launcher/Launcher.qml:113` toggles a surface inside
an already-running shell; that does not apply here.)

Touches:

- `.config/hypr/scripts/idle:44` — `lock_cmd` becomes `pidof -x qs-lock || qs -c lock`
- `.scripts/theme-apply:164` — generates `colors-hyprlock.conf`; the new lock
  reads `common/Theme.qml` instead, so that generated file becomes dead
- `.config/hypr/hyprlock.conf` — delete only after phase 4 passes

### 4. proving it before trusting it

- test from a second TTY with a shell already logged in
- lock, confirm face unlock, confirm password fallback, confirm both screens
- confirm `before_sleep_cmd` still locks ahead of suspend (idle script comment
  at the top of `.config/hypr/scripts/idle` calls this out)
- **cover the camera and lock.** The case that actually strands you is howdy
  failing to match while `responseRequired` never fires, so no password field
  ever appears. Test this from the TTY before deleting `hyprlock.conf`.

## risks

- **ext-session-lock is fail-secure by protocol.** If the lock process crashes
  while locked, the compositor keeps the session locked and blank with no
  unlock path. Recovery is a TTY. This is correct behaviour, and it is why the
  lock gets its own instance: run it inside the bar's shell and a crash in the
  launcher, a notification or `BatteryGuard` strands the whole session. That
  would be strictly worse than hyprlock today — it is the one thing this swap
  makes worse, and the separate instance is what cancels it.
- Wrong PAM order in `/etc/pam.d/quickshell-lock` = no way to authenticate.
- Face unlock is weaker than a password. An IR-capable photo can beat howdy.
  Do not wire it to anything that matters more than the session.
- Keep hyprlock installed and its bind reachable until phase 4 passes.

## not doing unless needed

- `linux-enable-ir-emitter` — the 13% frame matched in ambient light. If phase
  1 passes, skip the package.
