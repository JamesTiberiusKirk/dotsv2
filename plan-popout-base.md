# One base component for the bar popouts

Files today: `.config/quickshell/bar/Bar.qml` (3851 lines), `.config/quickshell/common/AttachedPanel.qml`, `.config/quickshell/common/Menu.qml`, `.config/quickshell/common/Sys.qml`.

## Problem
12 popouts, each hand-rolled. Adding one means editing six places.

| Duplicated thing | Copies |
|---|---|
| `PanelWindow` header, ~18 identical lines | 11 |
| `QtObject { property bool open }` state stub | 12 |
| `closeIslandPopouts()` body lines | 12 |
| `popoutsByName` entries | 12 |
| `anyPopoutOpen` OR-chain terms | 12 |
| Hardcoded bar-widget list in `Menu.qml` | 12 |

Bar.qml splits 990 lines of bar chrome to 2860 lines of popout.

Already exists, reuse don't replace:
- `common/AttachedPanel.qml` — card look, grow animation, j/k/h/l/Esc nav
- `ListPopout` (`Bar.qml:3749`) — wraps the header but also owns its content, so only docker/vm use it. Its header folds into the base; its body (empty-state line, name/status rows) becomes `component StatusList`, still used by exactly docker and vm.

## Two stages
Stage 2 alone is a ~2800-line diff. If behaviour changes inside it, a moved line and a broken line look identical. Stage 1 makes every popout the same shape first, so stage 2 is cut-and-paste, reviewable file by file.

## Stage 1 — the base component
New file `common/Popout.qml`, a `PanelWindow` that owns everything shared.

Owns:
- card look, padding, grow-out animation (delegates to `AttachedPanel`)
- position: finds its own bar button, flips to stay on screen (`panel.attachedPanelX`, `popoutTop`, `popoutLeft`)
- open/close: toggle from the button, click-away via `HyprlandFocusGrab`, opening one closes the rest
- keyboard: `WlrLayershell.keyboardFocus`, `panel.navOn` / `navFocus`
- tabs: chips, current tab, arrow/h/l switching
- registration: adds itself to `panel.popouts`; the bar and menu derive from that

Options, each one backed by variation that exists today:

| Option | Default | Why it is real |
|---|---|---|
| `name` | required | registration key, also the button it anchors to |
| `icon` | required | menu row icon |
| `width` | 320 | 10 distinct values in use: 240 250 280 300 300 320 320 340 340 360 |
| `spacing` | 8 | 8 is the common case; trayCol 2, pwrCol 6, lpCol 6, dispCol 10 |
| `title` | "" | calendar and docker/vm draw a DemiBold header, the other 10 do not |
| `tabs` | `[]` | the list of tab names. Empty draws no chips and behaves exactly like today. This is the ONLY tab knob. |
| `available` | true | clanker's row is gated on `Clanker.agents.length > 0` |

Tab look and position are hardcoded, not configurable: a horizontal chip row across the top, current one bold with an accent underline, matching the clanker panel. One style, no switch.

Not adding until something wants it: tab position, tab style, per-popout colours, resizable width. The base is the one place to add them later, which is the point.

### Anchoring: one `cell` property, no registry
`Popout { cell: backlightCell }`. The base computes the offset with `panel.offsetOf(cell)`, which walks the parent chain to the panel summing `x` (or `y` when vertical).
- kills the per-popout `sourceX` / `sourceWidth` pair, which today spells out `panel.pos(rightRow) + panel.pos(powerIsland) + panel.pos(backlightCell)`
- stays reactive: a QML binding captures every property read during evaluation, including inside a called function. `panel.pos(it)` is already a function call inside these bindings and re-evaluates fine today, so a recursive walk reading the same `x` properties behaves the same. A single `mapToItem` would NOT be reactive and would go stale when the bar flips vertical.
- **rejected**: a name-keyed anchor registry. `panel.anchors` collides with the built-in grouped property every Item has, and a map filled by `Component.onCompleted` fires no change signal, so every popout would position at 0. Same class of bug as the `monitors` array in the display work.
- `ListPopout` already injects `cell` this way. It only gets away with hardcoding the row and island because both its users share them.
- stage 2 cost: a popout file takes two injected properties, `panel` and `cell`.

### Tabs API
No new type. The base owns `currentTab` and draws the chips from `tabs`. Content groups itself with `visible: popout.currentTab === "screen"`, which is exactly what the display popout does now minus the chip drawing.

### Registry replaces the lists
Registration is for close-all, name lookup and the menu. It does NOT do anchoring.
- `panel.popouts` — self-registered instances. Register with `panel.popouts = panel.popouts.concat(this)`, never `push`: an in-place array mutation fires no change signal and every derived binding goes stale.
- `popoutsByName` and `anyPopoutOpen` derive from it
- `closeIslandPopouts()` loops it, but keeps its first line, `Notifs.centerOpen = false`, OUTSIDE the loop. That line is not a popout, and dropping it silently stops the notification centre closing when a popout opens.
- **verify `anyPopoutOpen` stays reactive.** Today it is an explicit OR over 12 `.open` properties, so QML tracks all 12. As `popouts.some(p => p.open)` it depends on capture reaching through the iteration. It drives `Sys.barPopoutsOpen`, a counter, so a silent failure drifts rather than crashes. Test the change handler fires directly. Fallback: each Popout reports its own transition to a panel-side counter.
- `Sys.barPanels` = `[{name, icon}]`, assigned wholesale by the bar; several screens overwrite with the same list
- `Menu.qml` reads `Sys.barPanels` instead of its hardcoded 12. The launcher reads `Menu.items`, so it picks this up with no launcher change.

### Cells toggle by name
`panel.toggle("display")` replaces `const next = !dispPopout.open; closeIslandPopouts(); dispPopout.open = next`, repeated 12 times. The 12 `QtObject` state stubs die with it.

Convert one popout at a time, screenshot against the before, then the next. The staging argument applies inside stage 1 too: converting 12 at once is still a diff touching all 2860 lines.

Bar.qml after stage 1: roughly 3400 lines, every popout the same shape.

## Stage 2 — one file per popout
`bar/popouts/Display.qml`, `Power.qml`, `Audio.qml`, ... each a `Popout { name: ...; icon: ...; <rows> }`.
Bar.qml keeps the chrome, the cells, and 12 one-line instantiations passing `panel`.
Bar.qml after stage 2: roughly 1000 lines.
Move one popout at a time, verify, move the next.

## Check
- every popout opens, looks unchanged, closes on click-away
- keyboard: menu -> `bar/<name>` opens with focus, j/k walks, Return acts, Esc closes
- display popout tabs still switch
- opening one popout closes the others
- menu and launcher list all 12, clanker only when an agent exists
- screenshot each popout before and after, compare

## Stage 1: done
All twelve popouts run on `common/Popout.qml`. The transition shim is gone.

| | |
|---|---|
| Bar.qml before | 3851 lines |
| Bar.qml after | 3452 lines |
| `common/Popout.qml` | 189 lines |
| Net | about 400 lines of duplication removed |

- [x] `common/Popout.qml`, registered in `common/qmldir`
- [x] registry: `popouts`, `livePopouts`, `popoutsByName`, `anyPopoutOpen`, `toggle(name)`
- [x] all twelve converted: tray, calendar, display, power, tailscale, bluetooth, audio, network, system, clanker, docker, vm
- [x] 8 cell clicks rewritten to `panel.toggle("<name>")`; the 12 `QtObject` state stubs deleted
- [x] `ListPopout` rebased on `Popout`; docker and vm are now registered popouts
- [x] `Menu.qml` reads `Sys.barPanels`; the launcher follows through `Menu.items`
- [x] backdrop reads `panel.anyPopoutOpen` instead of its own list of nine
- [x] verified: registry holds 12, `popoutsByName` has all 12, `Sys.barPanels` has 12 with icons, `toggle()` opens, `Sys.barPopoutsOpen` increments, every popout renders

### Extra option the conversion forced
- `wantsKeys` — the network popout takes the keyboard for its passphrase field, which no other popout does. The base reduces to the original condition: `navOn(root) || (open && wantsKeys)`.

### Clanker's chips are the base's tabs too
First left as its own content, on the grounds that the base's tabs switch views
while clanker's chips select an agent out of a singleton. Converted anyway, so
there is exactly one tab system in the bar.

`tabs` is the agent labels, empty below two agents so a single-agent setup draws
no chips as before. `Clanker.selectedId` stays the source of truth; the popout
keeps it and `currentTab` in step with two handlers that compare before assigning,
which is what stops them bouncing the selection back and forth.

### Found while building
- **`panel` is a reserved name at the use site.** The bar declares `id: panel`, so a `property var panel` on Popout shadows it and `panel: panel` silently binds the popout to itself: it registers nowhere and never opens, with no error. The property is called `bar`, matching `Chrome { bar: panel }` which already did this.
- **Popout completes after the panel.** A nested PanelWindow's `Component.onCompleted` fires after its parent's, so the panel's own `onCompleted` cannot see the registry yet.
- **Registration order is not declaration order.** It is completion order, which came out reversed. `Sys.barPanels` sorts by name rather than depend on it.
- **`offsetOf` is 6px more accurate than the expression it replaces.** The old `pos(row) + pos(island) + pos(cell)` skipped the island's inner layout inset.
- **The layer appears a few seconds after load**, once content lays out. Checking `hyprctl layers` too early looks like a failure.
- **The backdrop only ever listed nine popouts.** Tray, docker and vm never dimmed it. Fixed by deriving it.

## Stage 2: done
Every popout lives in `bar/popouts/`, one file each, instantiated from Bar.qml as
`XPopout { bar: panel; cell: someCell }`.

| | |
|---|---|
| Bar.qml at the start of all this | 3851 lines |
| Bar.qml now | 1047 lines |

Files: AudioPopout 511, NetworkPopout 349, DisplayPopout 334, TailscalePopout 252,
PowerPopout 240, ClankerPopout 234, BluetoothPopout 161, CalendarPopout 105,
ResourcePopout 83, TrayPopout 86, ListPopout 59.

### Pulled into `common/` because the split broke them
- `ValueSlider` (201 lines) — declared inside the display popout but used by audio too. Inline components are file-scoped, so splitting the file made it invisible. Its default width is now `parent.width` instead of naming one popout's column.
- `PillBtn` (25 lines) — panel-level, 9 uses across power, audio and tailscale.

### Decoupled so a popout file needs nothing but `bar` and `cell`
- `panel.clockDate` exposed for the calendar, so the one `SystemClock` and its resume resync stay shared
- `panel.isOpen(name)` for a cell that lights while its own popout is open
- `svcWrap.toggle(obj)` deleted; the service island calls `panel.toggle("docker"|"vm"|"system")`
- `QsMenuAnchor` moved inside the tray popout, its only user

## Dismissal
Consolidated, no popout carries its own.

| Way out | Where it lives | Works when |
|---|---|---|
| Click outside | dismiss layer in Bar.qml | always |
| Escape | dismiss layer in Bar.qml | always |
| Escape | `AttachedPanel` | menu-opened, popout holds the keyboard |
| Second click on the cell | `panel.toggle(name)` | always |
| Focus grab cleared | `Popout` | menu-opened, or network's passphrase field |
| Bar hidden / side changed | `panel.closeIslandPopouts()` | always |

Escape is on the shared dismiss layer, not on `Popout`, on purpose. A popout that
asks for the keyboard whenever it is open is the documented network-popout bug:
Hyprland focuses a layer the moment it maps, and the second click on its own cell
never gets back to the bar. The dismiss layer stops at the bar's edge and holds no
focus grab, so cells keep their clicks.

### The dismiss layer must not take focus from a popout that holds it
Adding Escape broke every menu-opened popout: the launcher and menu rows appeared
to do nothing.

- `Sys.openPanel` sets `kbdNav`, so the popout arms its `HyprlandFocusGrab`
- the dismiss layer becomes visible at the same moment and asked for `OnDemand`
  keyboard focus
- Hyprland moved focus to the dismiss layer, which cleared the popout's grab,
  whose `onCleared` sets `open = false`

The popout opened and shut inside the same frame, with no error anywhere. Fixed by
gating the dismiss layer's focus on `panel.anyPopoutGrabbing`: it asks for the
keyboard only when no popout is holding it. A menu-opened popout keeps focus and
answers Escape through `AttachedPanel`; a mouse-opened one holds no grab, so the
dismiss layer can take focus and answer Escape itself.

Verified afterwards: all twelve open through `Sys.openPanel`, the path the menu and
launcher rows use.

**Still unverified:** there is no key-injection tool on this machine, so pressing
Escape was never actually exercised, only the focus routing it depends on. If a
cell stops closing on a second click, remove the `keyboardFocus` line on the
dismiss layer; Escape then works for menu-opened popouts only.

## Sideways navigation in tailscale
`j`/`k` walk the focus chain and mean "next row" everywhere in the bar. The
tailscale popout had two focus stops sitting side by side in the same row, so
reaching the IP meant pressing `j`, which moved right rather than down.

- the identity line: hostname and IP
- every peer row: name and IP, so ten peers cost twenty presses

Both are one stop now. Arrows, `h` and `l` pick which half is live, `Return`
copies that one, and the row draws a single focus ring. Same shape as the
calendar's month header and the popout tab row, which already worked this way.

`TsCopy` stopped being a tab stop of its own. It gained `selected` for the
highlight and `baseColor` so a peer row can keep its own online/offline colour
underneath.

### Left alone: the slider's trailing icon
`ValueSlider` has an optional trailing action, used only by the AirPods row to
fold its settings open. It is still its own stop, because that row has no key
free: `h`/`l` are the volume and `Return` makes the device default. One extra
stop on one conditional row is not worth inventing a fourth key convention for.
