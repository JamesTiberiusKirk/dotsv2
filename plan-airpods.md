# AirPods in the bar

Daemon: fork of librepods shipped inside github.com/thisisgm/omarchy-pods (`daemon/`), pinned commit `fff7fec600a5b9a61cdb40e93eccbcceb4b8f824`.
Clone of it sits in this session's scratchpad; re-clone with `git clone --depth 1 https://github.com/thisisgm/omarchy-pods` if needed.

## Issues to solve
- no AirPods battery in the Bt panel (bluez gives nothing for them)
- no AirPods controls anywhere (ANC / transparency / adaptive / CA / one-bud / ear detection)
- no AirPods icon in Bt panel or audio output list
- audio panel can't connect a paired-but-disconnected bt audio device and switch to it
- dots-link sync only knows yay, not local `pkgbuilds/`

Rules: no new bar cell. Everything lives in the existing Bt and Audio popouts in `.config/quickshell/bar/Bar.qml`.

## 1. dots-link builds local PKGBUILDs
File: `dots-link/pkgs.go` (called from `dots-link/sync.go:104` and `:229`).
- new lists: `.config/installed_packages/pkgbuilds-common.txt` and `pkgbuilds-<host>.txt`. Same parse as `parsePkgs`. Names = dir names under `pkgbuilds/`, must equal `pkgname`.
- `listedPackages` unchanged. Add `listedBuilds(dir, host)` reading the two new lists.
- `filterInstalled` works for both (pacman -Qq knows local packages).
- plan render: `build <name>` lines under the same "packages listed but not installed" section (`renderPkgPlan`).
- install: local ones first, `makepkg -si --needed` with `cmd.Dir = <dots>/pkgbuilds/<name>`, stdio attached, one confirm for all. Then yay for the rest as today.
- `--yes`: skip like yay path does (install.sh has its own loop at `install.sh:55`; leave it).
- test: `dots-link/pkgs_test.go` style already exists for the others? check `*_test.go`; one test for the list parse + split is enough.
- create `.config/installed_packages/pkgbuilds-common.txt` containing `librepods-omarchy`.

## 2. PKGBUILD
File: `pkgbuilds/librepods-omarchy/PKGBUILD`. Copy style from `pkgbuilds/qt6-languageserver/PKGBUILD`.
- `pkgname=librepods-omarchy`, `conflicts=(librepods librepods-git)`, `provides=(librepods)`
- `source=("omarchy-pods::git+https://github.com/thisisgm/omarchy-pods#commit=fff7fec600a5b9a61cdb40e93eccbcceb4b8f824")`, `sha256sums=(SKIP)`
- `depends=(qt6-base qt6-declarative qt6-connectivity libpulse openssl bluez)`, `makedepends=(cmake ninja qt6-tools pkgconf git)`
  - CMake wants Qt6 Quick QuickControls2 Widgets Bluetooth DBus LinguistTools + OpenSSL + pkgconf (`daemon/CMakeLists.txt:7-9`)
- build: `cmake -S omarchy-pods/daemon -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF && cmake --build build`
- package: `DESTDIR="$pkgdir" cmake --install build`. Installs `librepods`, `librepods-ctl`, desktop file, svg, systemd unit (harmless on runit).
- `makepkg -si` once by hand on binstar after writing it.

## 3. Autostart
File: `.config/hypr/base.lua`, inside the `hyprland.start` block (~line 309).
- `hl.exec_cmd("env QT_LOGGING_RULES=openpods.debug=false librepods --headless")`
- daemon needs bluez + session bus. Both up before Hyprland starts.
- state file: `$XDG_STATE_HOME/librepods/status.json` (`~/.local/state/librepods/status.json`). Written atomically on change, removed on daemon quit.
- control socket: `$XDG_RUNTIME_DIR/librepods.sock`, driven by `librepods-ctl <verb>`.

## 4. Pods singleton
New file: `.config/quickshell/common/Pods.qml`. Register in `common/qmldir` as `singleton Pods 1.0 Pods.qml`.
Pattern: `FileView` with `watchChanges: true; onFileChanged: reload()` like the layout file at `bar/Bar.qml:381`. Parse `JSON.parse(text())` in a try, missing file = daemon down.

status.json fields (schema_version 1, all one line):
- `connected` bool, `device_name`, `model_name`, `model_number`, `is_pro_series`, `is_headset` (Max: single battery)
- `left`/`right`: `{available, level, charging, in_ear}`; `case`/`headset`: `{available, level, charging}`. level -1 = unknown
- `noise_mode`: -1 unknown, 0 off, 1 anc, 2 transparency, 3 adaptive
- `adaptive_noise_level` 0-100, `conversational_awareness` bool, `one_bud_anc_mode` bool
- `ear_detection_behavior`: 0 pause when one out, 1 pause when both out, 2 disabled
- `lid_state`: 0 open, 1 closed, 2 unknown
- capability flags: `supports_noise_off`, `supports_noise_control`, `supports_adaptive`, `supports_conversational_awareness`, `supports_one_bud_anc`
- ignore the `*_total` counters

Expose: `up` (file present), `connected`, `name`, `left/right/case/headset` objects, `noiseMode`, `adaptiveLevel`, `ca`, `oneBud`, `earMode`, `supports*`, and `hasBattery`.
Verbs via one `Process` (`Quickshell.Io`), `function ctl(verb)`:
- `noise:off | noise:anc | noise:transparency | noise:adaptive`
- `adaptive:N` (only while noise_mode = 3)
- `ca:on|off`, `onebud:on|off`
- `ear:off | ear:one | ear:both`
- `connect`, `disconnect` exist too, not needed (Bt handles it)
Optimistic hold: the fork's Service.qml holds a pending value ~4 s so the row does not snap back while the daemon catches up. Do the cheap version: set the local prop on click, let the next file change overwrite.

## 5. AirPods icon
New file: `.config/quickshell/icons/airpods.svg`.
- take `proPath` from the fork's `AirPodsIcon.qml` (repo root). Its ink box is `x=0.25 y=26.25 w=37.5 h=25.75`, so `viewBox="0.25 26.25 37.5 25.75"`, one `<path d=... fill-rule="nonzero"/>`, no fill attr (Icon.qml recolours black via MultiEffect).
- `Icon { name: "airpods" }` then works everywhere.

## 6. Bt panel row
Files: `.config/quickshell/common/Bt.qml`, `bar/Bar.qml` ~2163-2230 (Repeater over `Bt.devices`).
- `Bt.devIcon`: return `"airpods"` when `device.name` contains "AirPods" (bluez icon is just `audio-headset`). Cheap, no lookup table.
- `Bt.isPods(device)` same test, used by the row.
- battery text: if `Bt.isPods(dev) && Pods.hasBattery` show `L 80  R 75  case 60` (skip parts with level -1, headset model shows one number). Charging: append the existing `battery-charging` icon or a `+`. Else the current bluez `%` text.
- low colour: same thresholds as now, applied to the lowest pod.

## 7. Audio panel: reconnect rows
File: `bar/Bar.qml` ~2556-2561 (`AudHead "output"` + `Repeater model: Audio.sinks`).
- new list in `Bt.qml`: `audioDevices` = paired, not connected, bluez icon matches headset/headphone/speaker/audio.
- after the sinks Repeater, a Repeater over `Bt.audioDevices`: dimmed row, `Icon` from `Bt.devIcon`, name, click → `Bt.toggle(dev)` and set `Audio.pendingBt = dev.name`.
- in `common/Audio.qml`: `property string pendingBt`; on `sinks` change, if a sink's `devName`/`properties["api.bluez5.address"]`/name contains `pendingBt`, `setDefault(node)` and clear. Clear also on a 15 s timeout.
- check first whether wireplumber already switches: connect the pods with the panel open and watch `Audio.sink`. If it does, keep the explicit setDefault anyway, it is idempotent.
- sink row icon: `DevSlider` shows no icon today. Add `Icon` name `"airpods"` left of the label when `Audio.devName(node)` contains "AirPods". Small tweak in `ValueSlider` label row or a leading Icon in `DevSlider`.

## 8. Audio panel: AirPods accordion
File: `bar/Bar.qml`, directly under the sinks, visible when `Pods.connected`.
Pattern: wifi list fold at `bar/Bar.qml:2749-2790` (`netPopout.expanded`, `unfolded`, `fold()`). Add `property bool podsOpen` on `audPopout`, reset on close like `netPopout.expanded`.
Head row: airpods icon, `Pods.name`, chevron-down/up icon (icons exist), Return/click toggles. Battery summary on the right, same text as the Bt row.
Body (each gated on the capability flag):
- mode: four `PillBtn`s off / anc / transparency / adaptive, current one highlighted (`PillBtn` exists in the panel). Hide "off" when `!supportsNoiseOff`. Hide the row when `!supportsNoiseControl`.
- adaptive level: `ValueSlider` 0-100, only when `noiseMode === 3 && supportsAdaptive`, `onCommit → ctl("adaptive:"+v)`.
- `ToggleRow` "conversation awareness" → `ca:on/off`, when `supportsConversationalAwareness`.
- `ToggleRow` "one-bud anc" → `onebud:on/off`, when `supportsOneBudANC`.
- ear detection: three `PillBtn`s one / both / off → `ear:one|both|off`. Always shown.
- lid / in-ear: skip. Add if wanted later.
Keyboard nav: rows are `activeFocusOnTab` like everything else in the popout.

## Order
1 → 2 → run makepkg → 3 → restart daemon, confirm `~/.local/state/librepods/status.json` appears with pods connected → 4 → 5 → 6 → 7 → 8.
`qs` reloads on file change; check the log for QML errors after each step.

## Skipped
- fork's `Model.js` (229 lines) and `Service.qml` optimistic queue. JSON is a dozen fields, read directly.
- go-install handling in dots-link. Same split pattern extends when the first Go tool needs it.
- host-specific `pkgbuilds-<host>.txt` contents. Reader supports it, file not created.
