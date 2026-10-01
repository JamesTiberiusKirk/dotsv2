-- binstar — Asus Zenbook Duo UX8406CA, Artix/runit. VM shows Virtual-1 so these rules are inert there.
-- Every screen rule — both panels, the bottom one following the keyboard, and
-- any external — comes from monitors.lua, which reads the saved layout and
-- duo's state files. duo re-runs the same file live, so a reload lands on the
-- exact state duo last set instead of resetting it.
dofile(os.getenv("HOME") .. "/.config/hypr/monitors.lua")

-- duo (repo: duo/) — dock/undock watcher: eDP-2 off while the keyboard sits on it.
-- Logs to ~/.local/state/duo/log.
-- Also the target of the brightness binds (writes both panels). Session-scoped, no root.
hl.on("hyprland.start", function()
    hl.exec_cmd("~/go/bin/duo watch") -- Hyprland's PATH has no ~/go/bin
end)
