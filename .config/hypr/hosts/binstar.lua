-- binstar — Asus Zenbook Duo UX8406CA, Artix/runit. VM shows Virtual-1 so these rules are inert there.
-- Stacked panels, eDP-1 on top; positions are logical px (1800/1.5 = 1200).
hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5 })

-- eDP-2 is the panel under the keyboard, so its rule has to know whether the
-- keyboard is sitting on it. A static "enabled" rule here is re-applied by
-- every `hyprctl reload` — theme-apply does one on each light/dark switch,
-- SUPER+CTRL+C does one — which turned the covered panel back on with nothing
-- to explain it. duo's watcher only reacted to dock *changes*, so it never
-- corrected a reload it hadn't caused.
--
-- Asked of the hardware rather than of a file duo wrote, so this is still
-- right when duo is not running. The pogo-pin keyboard enumerates as
-- 0b05:1bf2 while docked (over bluetooth it is 1bf3, which does not cover the
-- panel and must not count).
-- Vendor and product matched in the same directory, exactly as duo/watch.go
-- does it — product alone would trust any device that happens to use 1bf2.
local function docked()
    local p = io.popen([[
        for d in /sys/bus/usb/devices/*/; do
            [ "$(cat "$d/idVendor" 2>/dev/null)" = 0b05 ] &&
            [ "$(cat "$d/idProduct" 2>/dev/null)" = 1bf2 ] && { echo yes; exit 0; }
        done
    ]])
    if not p then return false end
    local out = p:read("*a")
    p:close()
    return out:find("yes") ~= nil
end

if docked() then
    hl.monitor({ output = "eDP-2", disabled = true })
else
    hl.monitor({ output = "eDP-2", mode = "2880x1800@120", position = "0x1200", scale = 1.5 })
end

-- duo (repo: duo/) — dock/undock watcher: eDP-2 off while the keyboard sits on it.
-- Also re-asserts on a tick, so anything that moves the output behind its back
-- gets corrected; see duo/watch.go. Logs to ~/.local/state/duo/log.
-- Also the target of the brightness binds (writes both panels). Session-scoped, no root.
hl.on("hyprland.start", function()
    hl.exec_cmd("~/go/bin/duo watch") -- Hyprland's PATH has no ~/go/bin
end)
