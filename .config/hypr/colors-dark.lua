-- Hyprland color palette — dark (purple/black). Loaded by hyprland.lua via ~/.theme-mode.
hl.config({
    general = {
        col = {
            active_border   = { colors = { "rgba(a000ffaa)", "rgba(480073aa)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },
    },
    group = {
        col = {
            border_active          = "rgba(a000ffaa)",
            border_inactive        = "rgba(2a103dcc)",
            border_locked_active   = "rgba(ff0000aa)",
            border_locked_inactive = "rgba(2d2d2dcc)",
        },
        groupbar = {
            enabled             = true,
            height              = 28,
            font_size           = 13,
            gradients           = false,
            render_titles       = true,
            scrolling           = true,
            gaps_in             = 0,
            gaps_out            = 0,
            text_color_inactive = "rgba(d0d0d0ff)",
            text_color          = "rgba(ffffffff)",
            col = {
                active          = "rgba(a000ffff)",
                inactive        = "rgba(2a103dff)",
                locked_active   = "rgba(ff0000ff)",
                locked_inactive = "rgba(2d2d2dff)",
            },
        },
    },
})
