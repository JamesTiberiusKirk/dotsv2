-- dellstar — intel laptop, Artix/runit.
-- Pin eDP-1 scale=1 so `hyprctl reload` doesn't fall back to DPI auto-scale (1.5).
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
