local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.font = wezterm.font 'Hack Nerd Font Mono'
config.font_size = 13.0
config.line_height = 1.0

config.color_scheme_dirs = { os.getenv 'HOME' .. '/.config/wezterm/colors' }

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = true

config.window_decorations = 'TITLE | RESIZE'
config.window_background_opacity = 1.0
config.macos_window_background_blur = 0

config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 500

config.keys = {
  {
    key = 'Return',
    mods = 'SHIFT',
    action = wezterm.action.SendString '\x1b\r',
  },
  { key = '1', mods = 'CTRL', action = wezterm.action.SendString '\x1b[49;5u' },
  { key = '2', mods = 'CTRL', action = wezterm.action.SendString '\x1b[50;5u' },
  { key = '3', mods = 'CTRL', action = wezterm.action.SendString '\x1b[51;5u' },
  { key = '4', mods = 'CTRL', action = wezterm.action.SendString '\x1b[52;5u' },
  { key = '5', mods = 'CTRL', action = wezterm.action.SendString '\x1b[53;5u' },
  { key = '6', mods = 'CTRL', action = wezterm.action.SendString '\x1b[54;5u' },
  { key = '7', mods = 'CTRL', action = wezterm.action.SendString '\x1b[55;5u' },
  { key = '8', mods = 'CTRL', action = wezterm.action.SendString '\x1b[56;5u' },
  { key = '9', mods = 'CTRL', action = wezterm.action.SendString '\x1b[57;5u' },
}

local theme_mode_file = os.getenv 'HOME' .. '/.theme-mode'
local function read_theme_mode()
  local f = io.open(theme_mode_file, 'r')
  if f then
    local mode = f:read '*l'
    f:close()
    return mode
  end
  return 'dark'
end

local dark_colors = {
  foreground = '#E6E6E6',
  background = '#000000',
  cursor_bg = '#00FF5F',
  cursor_fg = '#000000',
  selection_bg = '#2A2A2A',
  selection_fg = '#FFFFFF',
  ansi = {
    '#000000', '#CC0000', '#00CC66', '#D7AF00',
    '#005FDD', '#AF00AF', '#00AFAF', '#E6E6E6',
  },
  brights = {
    '#4D4D4D', '#FF3333', '#33FF99', '#FFD700',
    '#3399FF', '#FF33FF', '#33FFFF', '#FFFFFF',
  },
}

local light_colors = {
  foreground = '#3c3836',
  background = '#fbf1c7',
  cursor_bg = '#79740e',
  cursor_fg = '#fbf1c7',
  selection_bg = '#d5c4a1',
  selection_fg = '#282828',
  ansi = {
    '#3c3836', '#9d0006', '#79740e', '#b57614',
    '#076678', '#8f3f71', '#427b58', '#665c54',
  },
  brights = {
    '#928374', '#cc241d', '#98971a', '#d79921',
    '#458588', '#b16286', '#689d6a', '#282828',
  },
}

local function apply_theme(mode)
  if mode == 'light' then
    config.colors = light_colors
  else
    config.colors = dark_colors
  end
  config.window_frame = mode == 'light' and {
    active_titlebar_bg = '#ebdbb2',
    inactive_titlebar_bg = '#ebdbb2',
  } or {
    active_titlebar_bg = '#0d0d0d',
    inactive_titlebar_bg = '#0d0d0d',
  }
end

apply_theme(read_theme_mode())

wezterm.on('window-config-reloaded', function(window)
  apply_theme(read_theme_mode())
end)

wezterm.on('update-right-status', function(window, pane)
  local mode = read_theme_mode()
  if mode == 'light' then
    window:set_right_status(wezterm.format { { Text = '  ☀  ' } })
  end
end)

return config
