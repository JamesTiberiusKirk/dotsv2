-- Hyprland color palette — light (gruvbox-inspired). Loaded by hyprland.lua via ~/.theme-mode.
hl.config({
    general = {
        col = {
            active_border   = { colors = { "rgba(b57614ee)", "rgba(d79921ee)" }, angle = 45 },
            inactive_border = "rgba(d5c4a1aa)",
        },
    },
    group = {
        col = {
            border_active          = "rgba(b57614ee)",
            border_inactive        = "rgba(c8b78fe0)",
            border_locked_active   = "rgba(cc241dee)",
            border_locked_inactive = "rgba(cfc1a0e0)",
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
            text_color_inactive = "rgba(504945ff)",
            text_color          = "rgba(3c3836ff)",
            col = {
                active          = "rgba(b57614ff)",
                inactive        = "rgba(ebdbb2ff)",
                locked_active   = "rgba(cc241dff)",
                locked_inactive = "rgba(d5c4a1ff)",
            },
        },
    },
})
