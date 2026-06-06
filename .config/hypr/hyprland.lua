-- ============================================================================
-- Hyprland entry point (Lua).
-- Since Hyprland 0.55, if this file exists it is loaded INSTEAD of hyprland.conf.
-- The check is startup-only, so hyprland.conf stays as an instant fallback:
-- delete/rename this file and restart Hyprland to go back.
--
-- Load order: base -> colors (theme) -> binds -> host overlay.
-- require() in Hyprland is a custom per-call scope and re-runs on reload,
-- so theme switching (theme-apply writes ~/.theme-mode + hyprctl reload) works.
-- ============================================================================

local function hostname()
    local h = os.getenv("HOSTNAME")
    if h and #h > 0 then return h end
    local f = io.open("/etc/hostname")
    if f then
        local s = f:read("l")
        f:close()
        if s and #s > 0 then return s end
    end
    return "unknown"
end

local function theme_mode()
    local f = io.open(os.getenv("HOME") .. "/.theme-mode")
    if f then
        local s = f:read("l")
        f:close()
        if s == "light" then return "light" end
    end
    return "dark"
end

require("base")
require("colors-" .. theme_mode())
require("binds")
require("hosts/" .. hostname())
