# plan: bar control center (fold indicators into one panel)

Mockup: https://fraedi.ai/artifacts/a2770d4b-3735-4c7b-a310-252d15df0add

## issues to solve

- Too many indicators in the bar. No way to hide the ones you rarely look at.
- Want a macOS style Control Center: one cell, a panel of tiles.
- Every indicator is customisable: in the bar, in the panel, or both.
- Clicking a tile morphs the panel card into that indicator's popout. No second window popping up.
- Popouts must open in the right place, whether their cell is in the bar or folded.

## agreed design

- Sliders cell (`tune-variant`) at the end of the status island opens it.
- Two switches per indicator: `pinned` (bar) and `inCC` (panel). At least one always on.
- Pin on a tile toggles the bar. Hover shows it.
- Right-click a tile removes it from the panel. Not pinned either: it goes back to the bar.
- `+` tile at the end morphs the card into an "add" list.
- Every indicator is eligible, left island and tray island too. Not eligible: mic dot (privacy), the sliders cell, the bell (for now, see below).
- A pinned indicator keeps its usual island.
- Defaults: panel = wifi, bt, tailscale, battery, sound, display, kbd light. Bar = wifi, battery, sound + everything not in the panel.
- Tiles in bar order. No drag reorder.
- Menu opened: j/k walk tiles, Return opens, Esc back.
- No "Edit bar" button.

## the morph cannot resize the window

- Each popout today is its own `PanelWindow` (`common/Popout.qml`). Two windows cannot melt into each other.
- Resizing a layer surface every frame = a Hyprland configure round-trip per frame. Stutters.
- Fix:
  - CC is one `PanelWindow` at a fixed size: widest page (380) x tallest page, plus slide room along the bar.
  - Transparent. `mask: Region` follows the card, so clicks outside it pass through (same trick as `bar/Bar.qml` `mask`).
  - Only the inner card animates: x, width, height. Content crossfades.
  - Vertical bar (left/right): animate y and height instead. Placement via the existing `popoutTop` / `popoutLeft` in `bar/Bar.qml`.

## one window for every popout

- Decided 2026-10-09: one card window per screen hosts every popout AND the CC.
- 11 popout windows become 1. Focus grab, open counters, click-away live in one place.
- Pinned cell click: card grows under that cell. Tile click: card morphs in place. Popout to popout: morphs too.
- `common/Popout.qml` stops being a `PanelWindow`. It becomes the body a host shows.
- Cost: every popout changes in phase a. Test all of them after it.

## popout content: no split needed (built)

- One host means a page is never shown twice. So no `*Body.qml` split.
- `common/Popout.qml` is now a plain `Item` page with the same API (`open`, `inputs`, `tabs`, `contentWidth`). Added `back` + `goBack()`.
- `bar/PopoutHost.qml`: the one card window. Fixed size, masked to the card, Behaviors morph x/y/width/height.
- First open after closed: Behaviors held off ~50ms (`settled`) so the card does not grow from a stale height.
- Only popout file changed: `bar/popouts/TrayPopout.qml` (menu anchor window).
- Notifications: `notifs/NotifCenter.qml` is two `PanelWindow`s, not a `Popout`. Out of scope for now: the bell stays bar-only, not eligible for the CC.

## build status (2026-10-09)

- All phases built in a scratch copy, lint clean, loads clean (`Configuration Loaded`).
- Nothing interactive tested: Claude's shell has no Hyprland socket or DBus.
- Not deployed yet: the user copies it in.

## the CC must join the popout registry

- `bar/Bar.qml`: `popouts` list, `anyPopoutOpen`, `anyPopoutGrabbing`, `closeIslandPopouts`, the dismiss layer.
- `Sys.barPopoutsOpen` / `Sys.barPopoutsGrabbing` counters. Miss these and Hyprland's submap is decided off stale counts.
- Focus grab clearing closes a popout. CC must follow the same rules (see the comments in `bar/Bar.qml` around `navFocus`).

## folded indicators still have to open

- `onTogglePanel` in `bar/Bar.qml` and the `bar/<panelName>` rows in `common/Menu.qml`.
- Pinned: open its own popout, as today.
- Folded: open the CC straight on that indicator's page.
- Anchor: `Popout.offsetOf(cell)` reads layout positions. A hidden cell is a bad anchor. Folded = anchor to the sliders cell.

## empty islands

- Unpin all of docker/system/AI, or all of tray/bell/clock: that island must go `visible: false`.
- `bar/Chrome.qml` draws capsules from `islandGeom` and its visible flag. Otherwise an empty capsule is left.

## state file

- `~/.local/state/qs-bar-pins`, same pattern as `qs-bar-side` in `common/ShellState.qml`.
- On load: enforce "in at least one place". A bad file must not make an indicator unreachable.
- New indicators added later: default to bar only.

## phases (each one is a go / no-go, tested on your machine)

- **a. extract bodies.** All popouts become `Popout` + `*Body.qml`. Zero visible change.
- **b. CC grid.** Sliders cell, tile panel, tiles hand off to the existing popouts. No morph yet.
- **c. morph.** Fixed-size CC window, card animates into the body, back arrow.
- **d. customise.** Pins, `+` add list, right-click remove, state file, empty islands, menu routing.
