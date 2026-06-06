-- deathstar — nvidia desktop, Artix/runit.
-- Layout replicated from autorandr profile `desktop-4`:
-- DP-1 = Acer VG271U, DP-2 = HSG HP245HJB, DP-3 = Philips 224E, HDMI-A-1 = Dell P2225H
hl.monitor({ output = "DP-2",     mode = "1920x1080@60",  position = "2240x0",    scale = 1 })
hl.monitor({ output = "DP-3",     mode = "1920x1080@60",  position = "0x1080",    scale = 1 })
hl.monitor({ output = "DP-1",     mode = "2560x1440@144", position = "1920x1080", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "preferred",     position = "4480x1080", scale = 1 })
