-- ============================================================================
-- Hyprland — base configuration (look & feel, input, devices, rules, autostart).
-- Keybinds live in binds.lua; theme colors in colors-{dark,light}.lua;
-- per-host monitors/env in hosts/<hostname>.lua. All required from hyprland.lua.
-- ============================================================================

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------
hl.env("XCURSOR_SIZE",         "24")
hl.env("HYPRCURSOR_SIZE",      "24")
hl.env("XDG_CURRENT_DESKTOP",  "Hyprland")
hl.env("QT_QPA_PLATFORM",      "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("TERMINAL",             "wezterm")
hl.env("QS_ICON_THEME",        "Adwaita") -- tray/menu icons; Adwaita inherits AdwaitaLegacy for the old names

-----------------------
---- LOOK AND FEEL ----
-----------------------
-- Layouts persisted by layout-switcher.sh in ~/.config/hypr/.layout:
-- "*=<global default>" plus "N=<layout>" per-workspace overrides. Re-read on
-- every reload, so picks survive reload/restart. Switcher also applies live
-- via `hyprctl eval` (keyword no-ops under the lua config).
local layouts = { default = "dwindle" }
do
    local f = io.open(os.getenv("HOME") .. "/.config/hypr/.layout")
    if f then
        for line in f:lines() do
            local k, v = line:match("^(%S+)=(%S+)$")
            if k == "*" then
                layouts.default = v
            elseif k then
                layouts[k] = v
            end
        end
        f:close()
    end
end
for ws, l in pairs(layouts) do
    if ws ~= "default" then
        hl.workspace_rule({ workspace = ws, layout = l })
    end
end

hl.config({
    general = {
        gaps_in          = 5,
        gaps_out         = 5,
        border_size      = 2,
        resize_on_border = false,
        allow_tearing    = false,
        layout           = layouts.default,
        -- border colors are set in colors-{dark,light}.lua
    },

    decoration = {
        rounding         = 12,
        rounding_power   = 2.0, -- plain arc: superellipse (4.0) renders jagged on deathstar/nvidia
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a, -- rgba(1a1a1aee)
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status  = "master",
        orientation = "center", -- master centered, stack splits left/right => 3 cols
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },

    ecosystem = {
        no_donation_nag = true,
    },

    cursor = {
        inactive_timeout = 3,
    },
})

----------------------
---- ANIMATIONS  -----
----------------------
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
-- slight-overshoot spring for popup entrances (quickshell layer surfaces)
hl.curve("popSpring",      { type = "spring", mass = 1, stiffness = 260, dampening = 22 })

hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    spring = "popSpring",    style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

---------------
---- INPUT ----
---------------
hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,
        repeat_delay = 300,
        repeat_rate  = 25,

        touchpad = {
            middle_button_emulation = 0,
            tap_to_click            = false,
            scroll_factor           = 0.2,
            natural_scroll          = true,
            clickfinger_behavior    = true,
        },
    },
})

-----------------
---- DEVICES ----
-----------------
-- Hyprland silently ignores device blocks for devices not present on the host,
-- so all device tweaks live here regardless of which machine they apply to.
hl.device({ name = "logitech-g203-prodigy-gaming-mouse", sensitivity = -1 })
hl.device({ name = "tpps/2-ibm-trackpoint",              sensitivity = -0.4 })
hl.device({
    name                 = "dell081c:00-044e:121f-touchpad",
    natural_scroll       = true,
    scroll_factor        = 0.2,
    clickfinger_behavior = true,
    tap_to_click     = false,
})
hl.device({
    name          = "dell081c:00-044e:121f-mouse",
    scroll_method = "on_button_down",
    scroll_button = 274,
    scroll_factor = 0.3,
})
-- binstar (Zenbook Duo) digitizers: without an output pin, they map across the
-- whole layout, so bottom-screen touches/pen strokes land on the top panel.
-- 9008 = top / 9009 = bottom (swap both pairs if they track the wrong panel).
hl.device({ name = "elan9008:00-04f3:4447", output = "eDP-1" })
hl.device({ name = "elan9009:00-04f3:4448", output = "eDP-2" })
hl.device({ name = "elan9008:00-04f3:4447-stylus", output = "eDP-1" })
hl.device({ name = "elan9009:00-04f3:4448-stylus", output = "eDP-2" })

-- Duo keyboard: keyd can't manage it (see .config/keyd/default.conf — grabbing
-- its combined keyboard+pointer node breaks the touchpad), so capslock→ctrl is
-- done in xkb here. Two names: pogo-docked reports Primax, bluetooth doesn't.
hl.device({ name = "primax-electronics-ltd.-asus-zenbook-duo-keyboard", kb_options = "ctrl:nocaps" })
hl.device({ name = "asus-zenbook-duo-keyboard", kb_options = "ctrl:nocaps" })
-- Palm rejection on the Duo keyboard's trackpad is disable-while-typing and
-- nothing else: the touchpad reports only X/Y/tracking-id — no MT_TOUCH_MAJOR,
-- no pressure, no MT_TOOL_TYPE — so libinput's size-, pressure- and
-- firmware-based palm detection all have nothing to work with. Set explicitly
-- because libinput defaults dwt OFF for touchpads it classes as external, which
-- a USB/bluetooth keyboard-with-trackpad is; the global default reads as true
-- but was never actually applied to this device.
hl.device({
    name                 = "primax-electronics-ltd.-asus-zenbook-duo-keyboard-touchpad",
    natural_scroll       = true,
    scroll_factor        = 0.2,
    clickfinger_behavior = true,
    tap_to_click         = false,
    disable_while_typing = true,
})
hl.device({
    name                 = "asus-zenbook-duo-keyboard-touchpad",
    natural_scroll       = true,
    scroll_factor        = 0.2,
    clickfinger_behavior = true,
    tap_to_click         = false,
    disable_while_typing = true,
})
hl.device({
    name                 = "apple-inc.-magic-trackpad",
    sensitivity          = -0.2,
    scroll_factor        = 0.15,
    natural_scroll       = true,
    clickfinger_behavior = true,
    tap_to_click         = false,
})

-------------------
---- WINDOWRULES --
-------------------
-- wezterm uses its own window_background_opacity (real per-pixel alpha) so the
-- hyprglass decoration shows through; a compositor opacity rule would fade the
-- glass along with the window.
hl.window_rule({
    name  = "picture-in-picture",
    match = { title = "^([Pp]icture.in.[Pp]icture)$" },
    float = true,
    pin   = true,
    size  = { 800, 450 },
})
hl.window_rule({ name = "blue-recorder-float", match = { class = "^(blue-recorder)$" }, float = true })
hl.window_rule({ name = "select-area-float",   match = { title = "^(Select Area)$" },   float = true })
hl.window_rule({ name = "satty-float",         match = { class = "^(com\\.gabm\\.satty|satty)$" }, float = true })
-- Bitwarden's popped-out extension window. Matched on class, not title: at map
-- time the title is still "_crx_<id>" and only becomes "Bitwarden" afterwards,
-- so a title rule never fires. The class is Brave's app-window id for the
-- extension (browser-specific; the extension id is stable, the trailing
-- profile name is not — prefix match so any profile on any host gets it).
hl.window_rule({ name = "bitwarden-float", match = { class = "^brave-nngceckbapebfimnlniiiahkandclblb-.*$" }, float = true })
-- Bitwarden's passkey prompt ("Confirm access") is a plain brave-browser popup
-- that maps as "New Tab - Brave" and renames afterwards, so no open-time rule
-- can catch it. Float it on the title change instead.
hl.on("window.title", function(w)
    if w.floating or w.class ~= "brave-browser" or w.title ~= "Confirm access - Brave" then return end
    hl.dispatch(hl.dsp.window.float({ action = "on", window = w }))
    hl.dispatch(hl.dsp.window.resize({ x = 900, y = 700, relative = false, window = w }))
    hl.dispatch(hl.dsp.window.center({ window = w }))
end)

-------------------
---- LAYERRULES ---
-------------------
-- quickshell popups: compositor blur + popin entrance. All GPU-side, so the
-- animation stays smooth no matter what the QML inside is doing.
-- ignore_alpha keeps the fully-transparent margins around the panel unblurred.
hl.layer_rule({
    name  = "qs-popups",
    match = { namespace = "^quickshell-(launcher|osd)$" },
    blur         = true,
    ignore_alpha = 0.05,
    animation    = "popin 80%",
})
-- Notification toasts slide themselves in from the right (notifs/NotifPopups.qml),
-- so no compositor animation at all — every one of them fought the slide.
-- popin scaled the whole surface, which is the toast stack, so cards shrank
-- in height and travelled on a diagonal. And the generic `layers` animation
-- covers *resize*, not just map: the surface grows for every card that
-- arrives, and Hyprland eased that growth by stretching the contents from the
-- old height to the new — the card was full-size in the buffer the whole time.
-- The map/unmap fade goes with it; the cards are already off-screen by then.
hl.layer_rule({
    name  = "qs-notifs",
    match = { namespace = "^quickshell-notifs$" },
    blur         = true,
    ignore_alpha = 0.05,
    no_anim      = true,
})
-- bar popouts (calendar/resources/notif center) animate themselves in QML
-- (grow-from-island), so no compositor popin — just blur + the layer fade.
hl.layer_rule({
    name  = "qs-popouts",
    match = { namespace = "^quickshell-popout$" },
    blur         = true,
    ignore_alpha = 0.05,
})
-- Notification drawer slides itself in (notifs/NotifCenter.qml); see qs-notifs.
hl.layer_rule({
    name  = "qs-drawer",
    match = { namespace = "^quickshell-drawer$" },
    blur         = true,
    ignore_alpha = 0.05,
    no_anim      = true,
})
hl.layer_rule({
    name  = "qs-backdrop",
    match = { namespace = "^quickshell-(notifs-)?backdrop$" },
    no_anim = true,
})

-------------------
---- AUTOSTART ----
-------------------
-- hyprland.start fires once at launch (not on reload), matching exec-once.
hl.on("hyprland.start", function()
    -- first: load plugins + reload config so glass rules exist before bars spawn
    hl.exec_cmd("~/.config/hypr/scripts/load-plugins.sh")
    hl.exec_cmd("qs") -- owns bar + notifications + launcher (see .config/quickshell)
    hl.exec_cmd("owncloud")
    hl.exec_cmd("hyprland-autoname-workspaces")
    hl.exec_cmd("~/.config/hypr/scripts/monitor-layout.sh")
    hl.exec_cmd("~/.config/hypr/scripts/monitor-watch.sh") -- hotplug: re-apply layout + wallpaper
    hl.exec_cmd("~/.scripts/menu/common/wallpaper.sh --current") -- swww, daemon spawned by the script
    hl.exec_cmd("~/.config/hypr/scripts/workspace-layouts.sh")
    hl.exec_cmd("~/.config/hypr/scripts/idle start") -- hypridle from generated conf
    hl.exec_cmd("cornd")
end)
