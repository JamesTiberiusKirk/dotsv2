-- gtmux server config. The client owns input (prefix + keybinds) and the
-- status bar (formats + colors), so almost everything lives in client.lua.
-- Session auto-naming: session_name is the fmt template (must contain %d)
-- for sessions created by a bare `gtmux new`. Defaults to tmux's "%d":
-- gtmux.set_option("session_name", "%d")

-- Windows numbered from 1 (tmux: set -g base-index 1)
gtmux.set_option("base_index", 1)

-- Allow apps to passthrough escape sequences (tmux: set -gq allow-passthrough on)
gtmux.set_option("allow_passthrough", true)

-- Vars refreshed from the attaching client's env into new panes (tmux:
-- set -g update-environment "...").
gtmux.set_option("update_environment",
	"DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS XDG_SESSION_ID XDG_RUNTIME_DIR SSH_AUTH_SOCK XAUTHORITY")

-- visual-activity off is gtmux's default already (tmux conf sets it explicitly).
