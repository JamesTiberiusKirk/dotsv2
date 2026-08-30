-- ============================================================================
-- Hyprland — plugin configuration (hyprglass).
-- Installed via hyprpm (repo: github.com/hyprnux/hyprglass), pinned to the
-- running Hyprland version. The plugin loads before config evaluation, so the
-- guard below passes whenever hyprpm has it enabled; it fails soft if the
-- plugin is ever disabled/missing instead of breaking the whole config.
-- ============================================================================

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    -- Defaults are already calibrated near Apple's liquid glass; only opt
    -- layer surfaces in globally, everything else stays stock. Refraction
    -- pushed past stock (0.6) for a more pronounced edge bend.
    hg.config({
        refraction_strength = 0.25,
        chromatic_aberration = 0.0,
        layers = { enabled = true },
    })

    -- Bar: mask_threshold sits above the bar's shadow alpha so shadows
    -- don't get boxed in glass.
    hg.layer("quickshell", { mask_threshold = 0.05 })
    hg.layer("quickshell-frame", { mask_threshold = 0.05 })
    -- Keep animated quickshell popups out of hyprglass; layer-surface glass is
    -- noticeably expensive and creates colored edge artifacts while panels move.
    -- hg.layer("quickshell-notifs", { mask_threshold = 0.05 })
    -- hg.layer("quickshell-launcher", { preset = "launcher", mask_threshold = 0.2 })

    -- Wallpaper picker: the surface is fullscreen but everything painted on it
    -- is the carousel band, so the threshold only has to clear the fully
    -- transparent rest. It cannot go high: mask_threshold culls sub-threshold
    -- pixels outright rather than leaving them un-glassed, and at 0.6 it ate
    -- both the picker's scrim and the band's own islandBorder (alpha 0.53).
    hg.layer("quickshell-wallpaper", { mask_threshold = 0.3 })
    -- Wallpaper caption (wallpaper/Info.qml): a 0.35-alpha pane, so the
    -- threshold only has to clear the transparent margin.
    hg.layer("quickshell-wallinfo", { mask_threshold = 0.05 })

    -- Launcher gets a frostier pane than the stock default (blur_strength 2.0).
    hg.preset("launcher", {
        blur_strength = 4.0,
    })

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
