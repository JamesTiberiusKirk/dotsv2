-- ============================================================================
-- Hyprland — plugin configuration (hyprglass).
-- Installed via hyprpm (repo: github.com/hyprnux/hyprglass), pinned to the
-- running Hyprland version. The plugin loads before config evaluation, so the
-- guard below passes whenever hyprpm has it enabled; it fails soft if the
-- plugin is ever disabled/missing instead of breaking the whole config.
-- ============================================================================

-- Look flags from ~/.scripts/glass: 1/0 files, missing = on. transparency off
-- wins over glass. Read on every load; the script reloads after a toggle.
local LOOK = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/glass/"
local function flag(name)
    local f = io.open(LOOK .. name)
    if not f then return true end
    local v = f:read("l")
    f:close()
    return v ~= "0"
end
local transparency = flag("transparency")
local glass = transparency and flag("glass") and hl.plugin.hyprglass ~= nil
-- bar + screen frame (one shape, bar/Chrome.qml): off = solid, nothing behind it
local bar = flag("bar")

if not transparency then
    hl.config({ decoration = { blur = { enabled = false } } })
elseif not glass then
    -- no glass: quickshell surfaces fall back to stock blur
    hl.layer_rule({
        name  = "qs-stock-blur",
        match = { namespace = bar and "^quickshell-(frame|popout|drawer|notifs|osd|launcher|wallpaper|wallinfo)$"
                                    or "^quickshell-(popout|drawer|notifs|osd|launcher|wallpaper|wallinfo)$" },
        blur         = true,
        ignore_alpha = 0.05,
    })
end

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    -- Stock look from the plugin's built-in presets; no hand-tuned globals.
    -- Earlier hand-tuning misread two units: tint_color is RRGGBBAA (alpha
    -- last), and edge_thickness is a fraction of the panel's smaller side
    -- (default 0.06), not pixels.
    hg.config({
        enabled = glass,
        layers = { enabled = true },
    })

    -- Stock glass minus the rainbow fringe, and a gentler edge bend: stock
    -- glass refracts at 8.0, which dragged coloured content behind the panel
    -- in a wide warped band along every edge.
    hg.preset("qs-glass", {
        inherits = "glass",
        chromatic_aberration = 0.0,
        refraction_strength = 3.0,
        -- lit edge line, light from top-left, darker on the far side: 3D edge
        bevel_strength = 0.6,
        bevel_size = 3.0,
        bevel_shadow = 0.5,
    })

    -- Bar + screen frame: plain subtle glass. qs-glass + contour on the
    -- chrome was tried 2026-10-28 and looked bad. Bar flag off = no glass.
    if bar then
        hg.layer("quickshell", { preset = "subtle", mask_threshold = 0.05 })
        hg.layer("quickshell-frame", { preset = "subtle", mask_threshold = 0.05 })
    end
    -- Popups on glass too. Was off before: layer-surface glass is expensive and
    -- showed colored edge artifacts while panels animated. Stock blur only
    -- comes back for these when glass is off (qs-stock-blur above).
    -- contour: each card gets its own edge/bevel following its rounded shape,
    -- even mid-animation; threshold sits above the panels' shadow alpha.
    hg.layer("quickshell-popout", { preset = "qs-glass", mask_mode = "contour", mask_threshold = 0.15 })
    hg.layer("quickshell-drawer", { preset = "qs-glass", mask_mode = "contour", mask_threshold = 0.15 })
    hg.layer("quickshell-notifs", { preset = "qs-glass", mask_mode = "contour", mask_threshold = 0.15 })
    hg.layer("quickshell-osd", { preset = "qs-glass", mask_mode = "contour", mask_threshold = 0.15 })
    -- shape: the glass edge, bend and bevel follow a box with the panel's own
    -- corner radius (Launcher.qml radius 14), not the square layer outline
    -- cut round by the mask, which clipped the bevel at the corners.
    hg.layer("quickshell-launcher", { preset = "qs-glass", mask_threshold = 0.2, shape = { radius = 14 } })

    -- Wallpaper picker: the surface is fullscreen but everything painted on it
    -- is the carousel band, so the threshold only has to clear the fully
    -- transparent rest. It cannot go high: mask_threshold culls sub-threshold
    -- pixels outright rather than leaving them un-glassed, and at 0.6 it ate
    -- both the picker's scrim and the band's own islandBorder (alpha 0.53).
    -- contour: the band gets its own edge and bevel instead of the screen edge.
    hg.layer("quickshell-wallpaper", { preset = "qs-glass", mask_mode = "contour", mask_threshold = 0.3 })
    -- Wallpaper caption (wallpaper/Info.qml): a 0.35-alpha pane, so the
    -- threshold only has to clear the transparent margin.
    hg.layer("quickshell-wallinfo", { preset = "qs-glass", mask_threshold = 0.05, shape = { radius = 10 } })

    -- ACCEPTED ISSUE: no glass on fullscreen windows.
    -- Hyprland skips decoration rendering for real-fullscreen windows
    -- (renderdata.decorate = false, src/render/Renderer.cpp), and hyprglass
    -- is a decoration — its pass never runs. Its `noblur` property also stays
    -- set from before the transition, so a fullscreened transparent window
    -- shows sharp transparency (no glass, no stock blur). Effect returns on
    -- un-fullscreen. Upstream: github.com/hyprnux/hyprglass/issues/54
    -- (milestoned v0.8.0 — re-test after `hyprpm update`). A renderWindow
    -- function-hook patch was prototyped 2026-08-03 but shelved untested.
end
