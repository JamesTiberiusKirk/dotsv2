-- ============================================================================
-- Hyprland — keybinds as data, with descriptions.
-- Single source of truth: this file also writes ~/.config/hypr/bindings.txt
-- (the Super+/ cheatsheet), replacing the old awk-based hypr-doc-gen.
-- ============================================================================

local terminal    = "wezterm"
local fileManager = "thunar"
-- The shell is quickshell (.config/quickshell): bar, notifications, menu.
local dsp         = hl.dsp

local doc = {}
-- every reg() call, kept so the popout submap can replay them (see bottom)
local regs = {}

-- reg(prefix, { {KEY, dispatcher, "description", flags?}, ... }, opts?)
-- opts.nav marks the ALT nav layer, which the launcher submap leaves out.
local function reg(prefix, list, opts)
    regs[#regs + 1] = { prefix = prefix, list = list, nav = opts and opts.nav }
    for _, b in ipairs(list) do
        local key, dispatcher, desc, flags = b[1], b[2], b[3], b[4]
        flags = flags or {}
        flags.description = desc
        hl.bind(prefix .. key, dispatcher, flags)
        doc[#doc + 1] = { keys = prefix .. key, desc = desc }
    end
end

-- Live keybind cheatsheet: build the list from `doc` at press-time and pipe it
-- straight into the menu. No file on disk; always in sync with the table.
local function show_binds()
    table.sort(doc, function(a, b) return a.keys < b.keys end)
    local lines = {}
    for _, d in ipairs(doc) do
        lines[#lines + 1] = string.format("%-40s %s", d.keys, d.desc or "")
    end
    local data = (table.concat(lines, "\n"):gsub("'", "'\\''"))
    hl.dispatch(hl.dsp.exec_cmd("printf '%s' '" .. data .. "' | ~/.scripts/qsmenu --prompt 'Hyprland bindings'"))
end

-- ---- Apps (SUPER) ----
reg("SUPER + ", {
    { "RETURN", dsp.exec_cmd(terminal),    "Open terminal" },
    { "E",      dsp.exec_cmd(fileManager), "Open file manager" },
    { "SPACE",  dsp.exec_cmd("qs ipc call menu toggle"), "Menu (apps, scripts, display, power)" },
    { "slash",  show_binds, "Show keybindings" },
    { "W",      dsp.exec_cmd("qs ipc call wallpaper toggle"), "Wallpaper picker" },
})

-- ---- Power key ----
-- elogind hands this key over (/etc/elogind/logind.conf.d/20-powerkey.conf sets
-- HandlePowerKey=ignore), so a tap opens the power menu instead of shutting the
-- laptop down. Every destructive entry there confirms first. Holding the key
-- still powers off, via HandlePowerKeyLongPress.
reg("", {
    { "XF86PowerOff", dsp.exec_cmd("qs ipc call menu at power"), "Power menu" },
})

-- ---- Nav layer: ALT + hjkl -> arrow keys ----
-- Done here rather than in keyd because keyd claims a whole device id, and the
-- bluetooth keyboard (0b05:1bf3) publishes its touchpad under the same id with
-- KEY events alongside its coordinates. keyd counts that as a keyboard, grabs
-- it, and replays it through its virtual pointer as absolute motion — the
-- cursor teleports to wherever your finger is. Pinning the right node needs a
-- per-node hash that only `sudo keyd monitor` can tell you, per keyboard, per
-- transport, forever.
--
-- Hyprland never touches the devices: it rewrites the chord after libinput has
-- already delivered it, so this works on every keyboard on every host with
-- nothing to enumerate. keyd's own [nav] layer still fires first for the docked
-- keyboard — same result, so the two agree rather than conflict.
reg("ALT + ", {
    { "H", dsp.send_shortcut({ mods = "", key = "left" }),  "Left (nav layer)",  { repeating = true } },
    { "J", dsp.send_shortcut({ mods = "", key = "down" }),  "Down (nav layer)",  { repeating = true } },
    { "K", dsp.send_shortcut({ mods = "", key = "up" }),    "Up (nav layer)",    { repeating = true } },
    { "L", dsp.send_shortcut({ mods = "", key = "right" }), "Right (nav layer)", { repeating = true } },
}, { nav = true })

-- ---- Session (SUPER SHIFT / SUPER CTRL) ----
reg("SUPER + SHIFT + ", {
    { "Q", dsp.window.close(), "Close window" },
    -- hyprlock directly, not loginctl lock-session: that signal needs a
    -- running hypridle, and the bind should lock even if it died
    { "L", dsp.exec_cmd("pidof hyprlock || hyprlock"), "Lock screen" },
    { "M", dsp.exec_cmd("zenity --question --title=\"Exit Hyprland\" --text=\"Really exit Hyprland?\" && hyprctl dispatch 'hl.dsp.exit()'"), "Exit Hyprland (confirm)" },
})
reg("SUPER + CTRL + ", {
    { "Q", dsp.exec_cmd("loginctl suspend"),              "Suspend" }, -- elogind (runit hosts have no systemctl)
    { "L", dsp.exec_cmd("~/.scripts/layout-switcher.sh"), "Layout switcher" },
})

-- ---- Window (SUPER) ----
reg("SUPER + ", {
    { "V", dsp.window.float({ action = "toggle" }),                           "Toggle floating" },
    { "F", dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Fullscreen" },
    { "P", dsp.exec_cmd("~/.config/hypr/scripts/pseudotile.sh"), "Pseudotile (60% x 100%)" },
})
reg("SUPER + SHIFT + ", {
    -- internal=0 (none) keeps the window tiled; client=2 tells the app it's fullscreen.
    { "F", dsp.window.fullscreen_state({ internal = 0, client = 2, action = "toggle" }), "Fake fullscreen" },
})

-- ---- Focus (vim) ----
-- Monocle and accordion stack windows spatially overlapped, so directional
-- focus is meaningless there (checked live at press time). Monocle: J/K cycle,
-- H/L stay directional (cross-monitor). Accordion: forwarded to the layout's
-- own layout_msg, which cycles on its axis and stays directional cross-axis.
-- Layout is per-workspace now (layout-switcher.sh), so ask the workspace.
local function focus_dir(dir)
    return function()
        local ws = hl.get_active_workspace()
        local layout = ws and ws.tiled_layout
        if layout == "monocle" and (dir == "u" or dir == "d") then
            -- tiled=true routes through the monocle algorithm's own cycle order
            hl.dispatch(dsp.window.cycle_next({ next = (dir == "d"), tiled = true }))
        elseif layout and layout:find("lua:accordion", 1, true) == 1 then
            hl.dispatch(dsp.layout("focus " .. dir))
        else
            hl.dispatch(dsp.focus({ direction = dir }))
        end
    end
end

reg("SUPER + ", {
    { "H", focus_dir("l"), "Focus left (cycle in h-accordion)" },
    { "L", focus_dir("r"), "Focus right (cycle in h-accordion)" },
    { "K", focus_dir("u"), "Focus up (cycle in monocle/v-accordion)" },
    { "J", focus_dir("d"), "Focus down (cycle in monocle/v-accordion)" },
})

-- ---- Move window (vim + shift) ----
reg("SUPER + SHIFT + ", {
    { "H", dsp.window.move({ direction = "l" }), "Move window left" },
    { "L", dsp.window.move({ direction = "r" }), "Move window right" },
    { "K", dsp.window.move({ direction = "u" }), "Move window up" },
    { "J", dsp.window.move({ direction = "d" }), "Move window down" },
})

-- ---- Workspaces (SUPER 1-0; SUPER SHIFT moves silently) ----
for i = 1, 10 do
    local key = (i == 10) and "0" or tostring(i)
    reg("SUPER + ",         { { key, dsp.focus({ workspace = i }),                       "Workspace " .. i } })
    reg("SUPER + SHIFT + ", { { key, dsp.window.move({ workspace = i, follow = false }), "Move window to workspace " .. i } })
end
reg("SUPER + ", {
    { "mouse_down", dsp.focus({ workspace = "e+1" }), "Next workspace (scroll)" },
    { "mouse_up",   dsp.focus({ workspace = "e-1" }), "Previous workspace (scroll)" },
})

-- ---- Cross-monitor workspace ops ----
reg("SUPER + SHIFT + ", {
    { "period", dsp.workspace.move({ monitor = "r" }), "Move workspace to right monitor" },
    { "comma",  dsp.workspace.move({ monitor = "l" }), "Move workspace to left monitor" },
    { "slash",  dsp.exec_cmd("~/.config/hypr/scripts/move-workspace-vertical.sh"), "Move workspace to vertical monitor" },
})

-- ---- Tabs (groups) ----
reg("SUPER + ", {
    { "bracketright", dsp.group.next(),                             "Next in group" },
    { "bracketleft",  dsp.group.prev(),                             "Previous in group" },
    { "G",            dsp.group.lock_active({ action = "toggle" }), "Lock active group" },
})
-- TODO(verify): no direct Lua dispatcher found for `moveoutofgroup` (was SUPER SHIFT G).
-- Left unbound until confirmed; see Dispatchers wiki.

-- ---- Mouse drag ----
reg("SUPER + ", {
    { "mouse:272", dsp.window.drag(),   "Move window (drag)",   { mouse = true } },
    { "mouse:273", dsp.window.resize(), "Resize window (drag)", { mouse = true } },
})

-- ---- Utilities ----
reg("SUPER + SHIFT + ", {
    { "C", dsp.exec_cmd("hyprctl reload && qs kill; qs -d"),            "Reload config" },
    { "T", dsp.exec_cmd("~/.scripts/theme-toggle"),                     "Toggle theme" },
    { "D", dsp.exec_cmd("qs ipc call notifs dismissAll"),               "Dismiss all notifications" },
    { "S", dsp.exec_cmd("~/.scripts/screenshot.sh"),                    "Screenshot" },
    { "A", dsp.exec_cmd("~/.scripts/extracttext.sh"),                   "OCR extract text" },
    { "N", dsp.exec_cmd("~/.config/hypr/scripts/nightlight toggle"),      "Toggle night light" },
})
reg("SUPER + ", {
    { "D", dsp.exec_cmd("qs ipc call notifs dismissLatest"), "Dismiss notification" },
    { "B", dsp.exec_cmd("qs ipc call shell toggle"), "Toggle bar" },
})

-- ---- Audio / brightness / media (no modifier) ----
reg("", {
    { "XF86AudioRaiseVolume",  dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),   "Volume up",   { locked = true, repeating = true } },
    { "XF86AudioLowerVolume",  dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),   "Volume down", { locked = true, repeating = true } },
    { "XF86AudioMute",         dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),  "Mute",        { locked = true, repeating = true } },
    { "XF86AudioMicMute",      dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),"Mute mic",    { locked = true, repeating = true } },
    -- duo (repo: duo/) drives every panel backlight on the host + the OSD;
    -- same 5%/1%-near-bottom stepping the old brightnessctl one-liner had
    { "XF86MonBrightnessUp",   dsp.exec_cmd("~/go/bin/duo brightness up"),   "Brightness up",   { locked = true, repeating = true } },
    { "XF86MonBrightnessDown", dsp.exec_cmd("~/go/bin/duo brightness down"), "Brightness down", { locked = true, repeating = true } },
    { "XF86AudioNext",         dsp.exec_cmd("playerctl next"),       "Next track",  { locked = true } },
    { "XF86AudioPause",        dsp.exec_cmd("playerctl play-pause"), "Play/pause",  { locked = true } },
    { "XF86AudioPlay",         dsp.exec_cmd("playerctl play-pause"), "Play/pause",  { locked = true } },
    { "XF86AudioPrev",         dsp.exec_cmd("playerctl previous"),   "Previous track", { locked = true } },
})

-- ============================ SUBMAPS ============================

-- Resize mode (i3-style). Enter with SUPER SHIFT R.
-- On accordion workspaces h/j/k/l adjust the layout's peek width instead
-- (the fold reveal); SHIFT variants stay plain window resizes.
reg("SUPER + SHIFT + ", { { "R", dsp.submap("resize"), "Resize mode" } })
local function resize_or_peek(dir, resize_dsp)
    return function()
        local ws = hl.get_active_workspace()
        local layout = ws and ws.tiled_layout
        if layout and layout:find("lua:accordion", 1, true) == 1 then
            hl.dispatch(dsp.layout((dir == "l" or dir == "j") and "grow" or "shrink"))
        else
            hl.dispatch(resize_dsp)
        end
    end
end
hl.define_submap("resize", function()
    hl.bind("h",            resize_or_peek("h", dsp.window.resize({ x = -50, y = 0,  relative = true })), { repeating = true })
    hl.bind("l",            resize_or_peek("l", dsp.window.resize({ x = 50,  y = 0,  relative = true })), { repeating = true })
    hl.bind("k",            resize_or_peek("k", dsp.window.resize({ x = 0,   y = -50, relative = true })), { repeating = true })
    hl.bind("j",            resize_or_peek("j", dsp.window.resize({ x = 0,   y = 50,  relative = true })), { repeating = true })
    hl.bind("SHIFT + h",    dsp.window.resize({ x = -100, y = 0,   relative = true }), { repeating = true })
    hl.bind("SHIFT + l",    dsp.window.resize({ x = 100,  y = 0,   relative = true }), { repeating = true })
    hl.bind("SHIFT + k",    dsp.window.resize({ x = 0,    y = -100, relative = true }), { repeating = true })
    hl.bind("SHIFT + j",    dsp.window.resize({ x = 0,    y = 100,  relative = true }), { repeating = true })
    hl.bind("escape",       dsp.submap("reset"))
    hl.bind("return",       dsp.submap("reset"))
end)
doc[#doc + 1] = { keys = "[resize] h/j/k/l (+SHIFT)", desc = "Resize active window (accordion: peek width); Esc/Enter to exit" }

-- Swap-visible-workspaces mode (i3-style). Enter with SUPER Tab.
local swap_script = "~/.config/hypr/scripts/swap-workspaces.sh "
-- Bare Tab: two monitors swap outright, more than two the script enters the
-- direction submap itself.
reg("SUPER + ", { { "Tab", dsp.exec_cmd(swap_script), "Swap visible workspaces (3+ monitors: pick a direction)" } })
-- Each key swaps then exits the submap. Two descriptor binds per key: a
-- function-action inside a submap is silently dropped on Hyprland 0.55, so we
-- bind the exec and the submap-reset as separate dispatchers (same as resize).
hl.define_submap("swap", function()
    hl.bind("h",        dsp.exec_cmd(swap_script .. "left"))
    hl.bind("h",        dsp.submap("reset"))
    hl.bind("l",        dsp.exec_cmd(swap_script .. "right"))
    hl.bind("l",        dsp.submap("reset"))
    hl.bind("k",        dsp.exec_cmd(swap_script .. "up"))
    hl.bind("k",        dsp.submap("reset"))
    hl.bind("j",        dsp.exec_cmd(swap_script .. "down"))
    hl.bind("j",        dsp.submap("reset"))
    hl.bind("escape",   dsp.submap("reset"))
    hl.bind("return",   dsp.submap("reset"))
    hl.bind("SUPER + Tab", dsp.submap("reset"))
end)
doc[#doc + 1] = { keys = "[swap] h/j/k/l", desc = "Swap visible workspace with adjacent monitor; Esc/Enter/SUPER+Tab to exit" }

-- Popout mode: entered by the shell itself whenever a bar popout or the
-- notification drawer is open (Sys.anythingOpen), left when the last one
-- closes. It exists so Esc can close them — the popouts take no keyboard
-- focus, so the compositor has to catch the key.
--
-- A submap inherits nothing: while it is active the only binds that exist
-- are the ones declared in it. Keys still reach the app, but SUPER+SHIFT+S
-- and every other binding above went dead with a widget open. So every
-- reg() call is replayed in here, and Esc goes on top. Registered directly
-- with hl.bind, not reg(), so the cheatsheet does not list everything twice.
local function replay(skip_nav)
    for _, r in ipairs(regs) do
        if not (skip_nav and r.nav) then
            for _, b in ipairs(r.list) do
                hl.bind(r.prefix .. b[1], b[2], b[4] or {})
            end
        end
    end
end
hl.define_submap("popout", function()
    replay(false)
    hl.bind("escape", dsp.exec_cmd("qs ipc call popouts closeAll"))
    hl.bind("escape", dsp.submap("reset"))
    -- any other key closes the popouts too, without eating the keystroke:
    -- non_consuming lets it reach the focused window as usual
    hl.bind("catchall", dsp.exec_cmd("qs ipc call popouts closeAll"), { non_consuming = true })
end)

-- Launcher mode: entered by the launcher while it is open. The ALT nav layer
-- is a sendshortcut to the active *window*, and the launcher is a layer
-- surface — so with a menu open ALT+J went to the app behind it. Leaving
-- the nav layer out of this submap lets the raw chord reach the launcher,
-- which maps ALT+hjkl to arrows itself (launcher/Launcher.qml).
hl.define_submap("launcher", function()
    replay(true)
end)

