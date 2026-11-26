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

-- Workspaces (`gtmux ws`, prefix+P), migrated from ~/.config/workspacer/workspaces.yaml.
-- Projects live in ~/src/<workspace>/<project>; sessions are named
-- <prefix>/<project>. Config is read at daemon start: `gtmux upgrade` after edits.
local ws = gtmux.workspace

ws.root = "~/src"

local dev = {
	{
		name = "nvim",
		select_layout = "main-vertical",
		panes = {
			{ cmd = "nvim" },
			{},
		},
	},
	{
		name = "clanker",
	},
}

-- Sister repos: one window named after the label, nvim + shell.
local sister = {
	{
		select_layout = "main-vertical",
		panes = {
			{ cmd = "nvim" },
			{},
		},
	},
}

-- `new` scaffold (workspacer's: go module + README). Typed into the new
-- project's first pane; gtmux then commits and, with --gh, pushes.
local go = {
	name = "go",
	init = function(p)
		return {
			"go mod init github.com/" .. p.login .. "/" .. p.name,
			"printf '# %s\\n' " .. p.name .. " > README.md",
		}
	end,
}

-- All accounts use the one `gh` login (JamesTiberiusKirk).
ws.account({ name = "me", kind = "user", login = "JamesTiberiusKirk", auth = ws.ghcli_auth({}) })
ws.account({ name = "atom", kind = "org", login = "AtomSites", auth = ws.ghcli_auth({}) })
ws.account({ name = "sf", kind = "org", login = "SportFreelancers", auth = ws.ghcli_auth({}) })
ws.account({ name = "ff", kind = "org", login = "FyrmForge", auth = ws.ghcli_auth({}) })
ws.account({ name = "uw", kind = "org", login = "utilitywarehouse", auth = ws.ghcli_auth({}) })

ws.add({
	name = "ws",
	account = "me",
	prefix = "ws",
	default = true,
	layout = dev,
	templates = { go },
})

ws.add({
	name = "at",
	account = "atom",
	prefix = "at",
	layout = dev,
	templates = { go },
})

ws.add({
	name = "sf",
	account = "sf",
	prefix = "sf",
	layout = dev,
	templates = { go },
	projects = {
		["sportfreelancers.com"] = {
			sisters = {
				{ name = "product-docs", label = "docs", layout = sister },
			},
		},
	},
})

ws.add({
	name = "ff",
	account = "ff",
	prefix = "ff",
	home = "root", -- ⌂ home: session ff/home in ~/src/ff itself
	layout = dev,
	templates = { go },
	projects = {
		["framiworks.io"] = {
			sisters = {
				{ name = "framiworks-docs", label = "docs", layout = sister },
			},
		},
	},
})

ws.add({
	name = "uww",
	account = "uw",
	prefix = "uww",
	home = ".llm", -- ⌂ home: session uww/home in ~/src/uww/.llm
	layout = dev,
	templates = { go },
	projects = {
		["telecom-mobile"] = {
			sisters = {
				{ name = "telecom-mobile-manifests", label = "manifests", layout = sister },
			},
		},
	},
})

-- Single folders: one session each, named after the folder (`gtmux ws folders <name>`).
ws.folder({
	name = "dots",
	path = "~/.dots",
	layout = {
		{
			name = "profile",
			select_layout = "main-vertical",
			panes = {
				{ cmd = "nvim" },
				{},
			},
		},
	},
})

ws.folder({
	name = "notes",
	path = "~/Documents/notes",
	layout = {
		{
			name = "nvim",
			panes = {
				{ cmd = "nvim" },
			},
		},
	},
})
