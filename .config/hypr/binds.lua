-- ============================================================================
-- Hyprland — keybinds as data, with descriptions.
-- Single source of truth: this file also writes ~/.config/hypr/bindings.txt
-- (the Super+/ cheatsheet), replacing the old awk-based hypr-doc-gen.
-- ============================================================================

local terminal    = "alacritty"
local fileManager = "thunar"
local menu        = "wofi --show drun"
local dsp         = hl.dsp

local doc = {}

-- reg(prefix, { {KEY, dispatcher, "description", flags?}, ... })
local function reg(prefix, list)
    for _, b in ipairs(list) do
        local key, dispatcher, desc, flags = b[1], b[2], b[3], b[4]
        flags = flags or {}
        flags.description = desc
        hl.bind(prefix .. key, dispatcher, flags)
        doc[#doc + 1] = { keys = prefix .. key, desc = desc }
    end
end

-- ---- Apps (SUPER) ----
reg("SUPER + ", {
    { "RETURN", dsp.exec_cmd(terminal),    "Open terminal" },
    { "E",      dsp.exec_cmd(fileManager), "Open file manager" },
    { "R",      dsp.exec_cmd(menu),        "App launcher" },
    { "slash",  dsp.exec_cmd("wofi --dmenu --prompt 'Hyprland bindings' --width 700 --height 600 < ~/.config/hypr/bindings.txt"), "Show keybindings" },
})

-- ---- Session (SUPER SHIFT / SUPER CTRL) ----
reg("SUPER + SHIFT + ", {
    { "Q", dsp.window.close(), "Close window" },
    { "M", dsp.exec_cmd("zenity --question --title=\"Exit Hyprland\" --text=\"Really exit Hyprland?\" && hyprctl dispatch 'hl.dsp.exit()'"), "Exit Hyprland (confirm)" },
})
reg("SUPER + CTRL + ", {
    { "Q", dsp.exec_cmd("systemctl suspend"),         "Suspend" }, -- NOTE: runit host; verify suspend cmd
    { "L", dsp.exec_cmd("~/.scripts/layout-switcher.sh"), "Layout switcher" },
})

-- ---- Window (SUPER) ----
reg("SUPER + ", {
    { "V", dsp.window.float({ action = "toggle" }),                       "Toggle floating" },
    { "F", dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), "Fullscreen" },
    { "P", dsp.window.pseudo(),                                           "Pseudotile" },
})
reg("SUPER + SHIFT + ", {
    -- TODO(verify): fullscreenstate mapping; was `fullscreenstate, 2` (fake fullscreen)
    { "F", dsp.window.fullscreen_state({ internal = "fullscreen", action = "toggle" }), "Fake fullscreen" },
})

-- ---- Focus (vim) ----
reg("SUPER + ", {
    { "H", dsp.focus({ direction = "l" }), "Focus left" },
    { "L", dsp.focus({ direction = "r" }), "Focus right" },
    { "K", dsp.focus({ direction = "u" }), "Focus up" },
    { "J", dsp.focus({ direction = "d" }), "Focus down" },
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
})

-- ---- Tabs (groups) ----
reg("SUPER + ", {
    { "W",            dsp.group.toggle(),                  "Toggle group" },
    { "bracketright", dsp.group.next(),                    "Next in group" },
    { "bracketleft",  dsp.group.prev(),                    "Previous in group" },
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
    { "C", dsp.exec_cmd("hyprctl reload && pkill -USR2 -x waybar"), "Reload config" },
    { "T", dsp.exec_cmd("~/.scripts/theme-toggle"),                 "Toggle theme" },
    { "D", dsp.exec_cmd("dunstctl close-all"),                      "Dismiss all notifications" },
    { "S", dsp.exec_cmd("~/.scripts/screenshot.sh"),               "Screenshot" },
    { "A", dsp.exec_cmd("~/.scripts/extracttext.sh"),              "OCR extract text" },
    { "N", dsp.exec_cmd("~/.config/hypr/scripts/nightlight-toggle.sh"), "Toggle night light" },
})
reg("SUPER + ", {
    { "D", dsp.exec_cmd("dunstctl close"), "Dismiss notification" },
})

-- ---- Audio / brightness / media (no modifier) ----
reg("", {
    { "XF86AudioRaiseVolume", dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),   "Volume up",   { locked = true, repeating = true } },
    { "XF86AudioLowerVolume", dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),   "Volume down", { locked = true, repeating = true } },
    { "XF86AudioMute",        dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),  "Mute",        { locked = true, repeating = true } },
    { "XF86AudioMicMute",     dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),"Mute mic",    { locked = true, repeating = true } },
    { "XF86MonBrightnessUp",  dsp.exec_cmd("brightnessctl s 5%+"), "Brightness up",   { locked = true, repeating = true } },
    { "XF86MonBrightnessDown",dsp.exec_cmd("brightnessctl s 5%-"), "Brightness down", { locked = true, repeating = true } },
    { "XF86AudioNext",  dsp.exec_cmd("playerctl next"),       "Next track",  { locked = true } },
    { "XF86AudioPause", dsp.exec_cmd("playerctl play-pause"), "Play/pause",  { locked = true } },
    { "XF86AudioPlay",  dsp.exec_cmd("playerctl play-pause"), "Play/pause",  { locked = true } },
    { "XF86AudioPrev",  dsp.exec_cmd("playerctl previous"),   "Previous track", { locked = true } },
})

-- ============================ SUBMAPS ============================

-- Resize mode (i3-style). Enter with SUPER SHIFT R.
reg("SUPER + SHIFT + ", { { "R", dsp.submap("resize"), "Resize mode" } })
hl.define_submap("resize", function()
    hl.bind("h", dsp.window.resize({ x = -50, y = 0,  relative = true }), { repeating = true })
    hl.bind("l", dsp.window.resize({ x = 50,  y = 0,  relative = true }), { repeating = true })
    hl.bind("k", dsp.window.resize({ x = 0,   y = -50, relative = true }), { repeating = true })
    hl.bind("j", dsp.window.resize({ x = 0,   y = 50,  relative = true }), { repeating = true })
    hl.bind("SHIFT + h", dsp.window.resize({ x = -100, y = 0,   relative = true }), { repeating = true })
    hl.bind("SHIFT + l", dsp.window.resize({ x = 100,  y = 0,   relative = true }), { repeating = true })
    hl.bind("SHIFT + k", dsp.window.resize({ x = 0,    y = -100, relative = true }), { repeating = true })
    hl.bind("SHIFT + j", dsp.window.resize({ x = 0,    y = 100,  relative = true }), { repeating = true })
    hl.bind("escape", dsp.submap("reset"))
    hl.bind("return", dsp.submap("reset"))
end)
doc[#doc + 1] = { keys = "[resize] h/j/k/l (+SHIFT)", desc = "Resize active window; Esc/Enter to exit" }

-- Swap-visible-workspaces mode (i3-style). Enter with SUPER Tab.
reg("SUPER + ", { { "Tab", dsp.submap("swap"), "Swap workspaces mode" } })
local function swap_then_reset(dir)
    return function()
        hl.dispatch(dsp.exec_cmd("~/.config/hypr/scripts/swap-workspaces.sh " .. dir))
        hl.dispatch(dsp.submap("reset"))
    end
end
hl.define_submap("swap", function()
    hl.bind("h", swap_then_reset("left"))
    hl.bind("l", swap_then_reset("right"))
    hl.bind("k", swap_then_reset("up"))
    hl.bind("j", swap_then_reset("down"))
    hl.bind("escape", dsp.submap("reset"))
    hl.bind("return", dsp.submap("reset"))
end)
doc[#doc + 1] = { keys = "[swap] h/j/k/l", desc = "Swap visible workspace with adjacent monitor; Esc/Enter to exit" }

-- ==================== Write the cheatsheet ====================
local ok = pcall(function()
    local path = os.getenv("HOME") .. "/.config/hypr/bindings.txt"
    local f = io.open(path, "w")
    if not f then return end
    table.sort(doc, function(a, b) return a.keys < b.keys end)
    for _, d in ipairs(doc) do
        f:write(string.format("%-40s %s\n", d.keys, d.desc or ""))
    end
    f:close()
end)
local _ = ok
