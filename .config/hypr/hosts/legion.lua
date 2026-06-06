-- legion — AMD + NVIDIA hybrid laptop, Arch/systemd.
-- NVIDIA env vars (proprietary driver >= 555). If you see invisible cursor on an
-- older driver, also add: hl.config({ cursor = { no_hardware_cursors = true } })
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED", "0")
hl.env("NVD_BACKEND", "direct")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.monitor({ output = "eDP-1",   mode = "preferred", position = "-1920x0", scale = 1 })
hl.monitor({ output = "DVI-I-1", mode = "preferred", position = "0x0",     scale = 1 })
hl.monitor({ output = "DVI-I-2", mode = "preferred", position = "2560x0",  scale = 1 })
