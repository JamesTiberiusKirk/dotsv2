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

    -- Bar: whitelist the waybar namespace. mask_threshold sits above the
    -- bar's shadow alpha so shadows don't get boxed in glass.
    hg.layer("waybar", { mask_threshold = 0.05 })
    hg.layer("quickshell", { mask_threshold = 0.05 })
    -- Keep animated quickshell popups out of hyprglass; layer-surface glass is
    -- noticeably expensive and creates colored edge artifacts while panels move.
    -- hg.layer("quickshell-notifs", { mask_threshold = 0.05 })
    -- hg.layer("quickshell-launcher", { preset = "launcher", mask_threshold = 0.2 })

    -- Notifications and launcher get the same treatment.
    -- (dunst's layer namespace is "notifications", not "dunst")
    hg.layer("notifications", { mask_threshold = 0.05 })
    -- Launcher gets a frostier pane than the stock default (blur_strength 2.0).
    hg.preset("launcher", {
        blur_strength = 4.0,
    })
    hg.layer("wofi",  { preset = "launcher", mask_threshold = 0.2 }) -- above GTK's focused CSD shadow alpha, or the square shadow gets glassed (hard corners)

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
