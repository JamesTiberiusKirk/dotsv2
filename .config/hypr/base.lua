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

-----------------------
---- LOOK AND FEEL ----
-----------------------
hl.config({
    general = {
        gaps_in          = 5,
        gaps_out         = 5,
        border_size      = 2,
        resize_on_border = false,
        allow_tearing    = false,
        layout           = "dwindle",
        -- border colors are set in colors-{dark,light}.lua
    },

    decoration = {
        rounding         = 0,
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
        new_status = "master",
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
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
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
hl.device({
    name                 = "apple-inc.-magic-trackpad",
    sensitivity          = 0.5,
    natural_scroll       = true,
    clickfinger_behavior = true,
    tap_to_click         = false,
})

-------------------
---- WINDOWRULES --
-------------------
hl.window_rule({
    name    = "wezterm-opacity",
    match   = { class = "^(org\\.wezfurlong\\.wezterm)$" },
    opacity = "0.90 0.85",
})
hl.window_rule({
    name  = "firefox-picture-in-picture",
    match = { class = "^(firefox)$", title = "^(Picture-in-Picture)$" },
    float = true,
    pin   = true,
    size  = { 800, 450 },
})
hl.window_rule({ name = "blue-recorder-float", match = { class = "^(blue-recorder)$" }, float = true })
hl.window_rule({ name = "select-area-float",   match = { title = "^(Select Area)$" },   float = true })
hl.window_rule({ name = "satty-float",         match = { class = "^(com\\.gabm\\.satty|satty)$" }, float = true })
hl.window_rule({ name = "flameshot-float-pin", match = { class = "^(flameshot)$" }, float = true, pin = true })

-------------------
---- AUTOSTART ----
-------------------
-- hyprland.start fires once at launch (not on reload), matching exec-once.
hl.on("hyprland.start", function()
    hl.exec_cmd("dunst")
    hl.exec_cmd("~/.scripts/launch-waybar")
    hl.exec_cmd("pasystray")
    hl.exec_cmd("blueman-applet")
    hl.exec_cmd("owncloud")
    hl.exec_cmd("hyprland-autoname-workspaces")
    hl.exec_cmd("~/.config/hypr/scripts/monitor-layout.sh")
    hl.exec_cmd("swaybg -o '*' -i ~/Pictures/wallpapers/interior-of-a-barn.jpg -m fill")
    hl.exec_cmd("~/.config/hypr/scripts/workspace-layouts.sh")
    hl.exec_cmd("cornd")
end)
