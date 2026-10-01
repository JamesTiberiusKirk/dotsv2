-- The one place screen state becomes hl.monitor rules. Nothing else emits them.
--
-- Run by every config load (hosts/<host>.lua dofile()s it) and live by every
-- writer, which changes its own state file and then re-runs this:
--   hyprctl eval 'dofile(os.getenv("HOME").."/.config/hypr/monitors.lua") return ""'
-- Same inputs, same rules either way, so a reload can no longer reset a screen.
--
-- Inputs, one owner each:
--   kernel     which connectors are connected, each monitor's EDID identity,
--              the lid switch
--   layout     ~/.local/state/hypr/layouts/<profile>   monitor-layout.sh save|scale
--   duo        ~/.local/state/duo/screen-override,
--              $XDG_RUNTIME_DIR/duo/{mode,rotation}     duo (Zenbook Duo only)
--   powersave  $XDG_RUNTIME_DIR/ultrasave{,-modes}     .scripts/powersave
--
-- Never calls hyprctl: during a reload Hyprland is busy running this file, so a
-- hyprctl call would wait on itself. Files and /sys only.
--
-- Outside Hyprland (`lua monitors.lua`) there is no `hl`; the rules are printed
-- instead of applied. That is the dry run, and how monitor-layout.sh refreshes
-- the connector -> identity map below without touching the screens.

local HOME = os.getenv("HOME")
local STATE = os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")
local RUN = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local STORE = STATE .. "/hypr/layouts"

local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function value(path)
    local s = slurp(path)
    return s and s:match("^%s*(.-)%s*$") or nil
end

local function hostname()
    local h = os.getenv("HOSTNAME")
    if h and #h > 0 then return h end
    return value("/etc/hostname") or "unknown"
end

-- Layout used when a monitor has no saved line. Built-in panels are keyed by
-- connector (see identity()), so these match them directly.
local DEFAULTS = {
    binstar = {
        -- logical px: 1800 / 1.5 = 1200
        ["eDP-1"] = { mode = "2880x1800@120", pos = "0x0", scale = 1.5 },
        ["eDP-2"] = { mode = "2880x1800@120", pos = "0x1200", scale = 1.5 },
    },
}
local FALLBACK = { mode = "preferred", pos = "auto", scale = 1 }

-- Monitor identity from its EDID: maker, model name, serial. Layouts follow the
-- monitor, not the port, so a screen moved to another port keeps its layout and
-- a different screen on that port does not inherit it.
--
-- Built-in panels keep their connector name: they never move, and on the Duo
-- both report the exact same EDID (same panel model, serial 0).
local function identity(conn, dir)
    if conn:match("^eDP") then return conn end
    local e = slurp(dir .. "/edid")
    if not e or #e < 128 then return conn end
    -- bytes 8-9: three 5-bit letters, the PNP maker code (ACR = Acer)
    local m = e:byte(9) * 256 + e:byte(10)
    local maker = string.char(64 + math.floor(m / 1024) % 32, 64 + math.floor(m / 32) % 32, 64 + m % 32)
    -- descriptors at 54/72/90/108: tag 0xFC is the model name, 0xFF the serial
    local name, serial = "", ""
    for off = 55, 109, 18 do
        if e:byte(off) == 0 and e:byte(off + 1) == 0 then
            local txt = (e:sub(off + 5, off + 17):match("^[^\n]*"):gsub("[^%w]", ""))
            local tag = e:byte(off + 3)
            if tag == 0xFC then name = txt elseif tag == 0xFF then serial = txt end
        end
    end
    if name == "" then name = string.format("%02x%02x", e:byte(12), e:byte(11)) end
    if serial == "" then
        local n = e:byte(13) + e:byte(14) * 256 + e:byte(15) * 65536 + e:byte(16) * 16777216
        if n ~= 0 then serial = string.format("%x", n) end
    end
    return maker .. "-" .. name .. (serial ~= "" and ("-" .. serial) or "")
end

-- Connected outputs, from the kernel rather than the compositor: an output
-- Hyprland has disabled is still plugged in, and must keep its place in the key.
-- ponytail: globs every card; a multi-GPU host (legion) would pull in connectors
-- nobody scans out to. Filter by card when that host migrates.
local outputs, seen = {}, {}
local ls = io.popen("ls -d /sys/class/drm/card*-* 2>/dev/null")
if ls then
    for dir in ls:lines() do
        if value(dir .. "/status") == "connected" then
            local conn = dir:match("card%d+%-(.+)$")
            local id = identity(conn, dir)
            outputs[#outputs + 1] = { conn = conn, id = id }
            seen[id] = (seen[id] or 0) + 1
        end
    end
    ls:close()
end
-- two identical monitors without serials: tell them apart by port
for _, o in ipairs(outputs) do
    if seen[o.id] > 1 then o.id = o.id .. "@" .. o.conn end
end

local ids = {}
for _, o in ipairs(outputs) do ids[#ids + 1] = o.id end
table.sort(ids)
local profile = table.concat(ids, ",")

-- saved layout for this exact set of monitors: id,mode,pos,scale,transform
local saved = {}
for line in (slurp(STORE .. "/" .. profile) or ""):gmatch("[^\n]+") do
    local id, mode, pos, scale, tf = line:match("^([^,]+),([^,]+),([^,]+),([^,]+),?([^,]*)")
    if id then saved[id] = { mode = mode, pos = pos, scale = tonumber(scale), transform = tonumber(tf) or 0 } end
end

local defaults = DEFAULTS[hostname()] or {}
local rules = {}
for _, o in ipairs(outputs) do
    local r = saved[o.id] or defaults[o.conn] or FALLBACK
    rules[o.conn] = { mode = r.mode, pos = r.pos, scale = r.scale, transform = r.transform or 0 }
end

-- Zenbook Duo: duo decides the two panels' power, mirroring and rotation.
-- Rotation is not a per-panel transform: turning the machine turns the stack,
-- so stacked-on-top becomes side by side. Positions are logical px at scale 1.5
-- (1920x1200 landscape, 1200x1920 portrait). Sides as observed on the machine:
-- with the left edge up, the panel that was on top lands on the RIGHT.
local ROTATION = {
    ["normal"]    = { tf = 0 },
    ["bottom-up"] = { tf = 2, top = "0x1200", bottom = "0x0" },
    ["left-up"]   = { tf = 1, top = "1200x0", bottom = "0x0" },
    ["right-up"]  = { tf = 3, top = "0x0", bottom = "1200x0" },
}

local function docked()
    -- the pogo-pin keyboard is USB 0b05:1bf2 while it covers eDP-2 (over
    -- bluetooth it is 1bf3, which covers nothing). Vendor and product from the
    -- same device dir, as duo/watch.go docked() does.
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

local bottomOff = false
if rules["eDP-1"] and rules["eDP-2"] then
    local top, bottom = rules["eDP-1"], rules["eDP-2"]
    -- a manual `duo screen on|off` (or a layout preset) latches an override;
    -- without one the panel follows the keyboard
    local want = value(STATE .. "/duo/screen-override")
    if want ~= "on" and want ~= "off" then want = docked() and "off" or "on" end
    bottomOff = want == "off"

    local mode = value(RUN .. "/duo/mode") or "stacked"
    local rot = ROTATION[value(RUN .. "/duo/rotation") or "normal"] or ROTATION.normal
    if rot.tf ~= 0 then
        top.transform, bottom.transform = rot.tf, rot.tf
        top.pos, bottom.pos = rot.top, rot.bottom
    else
        top.transform, bottom.transform = 0, 0
    end
    if mode == "mirror-flip" then
        -- tent mode: the top panel faces whoever sits across from you
        top.transform = 2
    end
    if mode == "mirror" or mode == "mirror-flip" then
        bottom.mirror = "eDP-1"
    end
end

-- powersave drops each screen to its lowest refresh; the modes are computed by
-- .scripts/powersave (it can ask hyprctl, this file cannot)
if value(RUN .. "/ultrasave") == "1" then
    for line in (slurp(RUN .. "/ultrasave-modes") or ""):gmatch("[^\n]+") do
        local conn, mode = line:match("^(%S+)%s+(%S+)")
        if conn and rules[conn] then rules[conn].mode = mode end
    end
end

-- Clamshell: lid shut with an external plugged in → the built-in panels go
-- dark and Hyprland moves their workspaces onto the externals. elogind already
-- skips suspend while docked (HandleLidSwitchDocked=ignore; Docked=true with an
-- external connected), so all this has to do is stop lighting panels behind a
-- closed lid. Lid shut with no external: panels untouched, elogind suspends.
-- Re-run on every lid edge by the switch bind in binds.lua.
local clamshell = false
local lid = io.popen("cat /proc/acpi/button/lid/*/state 2>/dev/null")
if lid then
    local closed = (lid:read("*a") or ""):find("closed") ~= nil
    lid:close()
    if closed then
        for _, o in ipairs(outputs) do
            if not o.conn:match("^eDP") then clamshell = true end
        end
    end
end

-- connector -> identity for monitor-layout.sh save|scale, so there is one EDID
-- parser, not two
local map = io.open(RUN .. "/hypr-monitors", "w")
if map then
    map:write("profile ", profile, "\n")
    for _, o in ipairs(outputs) do map:write(o.conn, " ", o.id, "\n") end
    map:close()
end

local monitor = hl and hl.monitor or function(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = k .. "=" .. tostring(v) end
    table.sort(keys)
    print(table.concat(keys, " "))
end

for _, o in ipairs(outputs) do
    local r = rules[o.conn]
    if (o.conn == "eDP-2" and bottomOff) or (clamshell and o.conn:match("^eDP")) then
        monitor({ output = o.conn, disabled = true })
    elseif r.mirror then
        monitor({ output = o.conn, transform = 0, mirror = r.mirror, disabled = false })
    else
        -- mirror = "none" and disabled = false are not redundant: a rule that
        -- omits either leaves a previous mirror or a disabled output in place
        monitor({ output = o.conn, mode = r.mode, position = r.pos, scale = r.scale,
                  transform = r.transform, mirror = "none", disabled = false })
    end
end
