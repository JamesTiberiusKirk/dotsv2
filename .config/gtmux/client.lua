-- gtmux client config: chrome colors and toggles, applied per-attach.
-- Mirrors ~/.tmux.conf as closely as gtmux allows. Genuinely still missing:
-- no-prefix C-1..C-9 (terminals emit no distinct byte for Ctrl+digit); the
-- join-pane choose-window %% picker (use prefix+M then g, or join-pane -s/-t);
-- escape-time (N/A — no client-side ESC timer). Ceilings: status-keys vi is
-- plain typing (ESC cancels the prompt, so no modal editing — emacs gets the
-- C-u/C-w kill keys); choose-tree/choose-session pane preview is captured at
-- open, not live.

-- Options: one surface — gtmux.options.X = Y, with real Lua types (numbers and
-- bools, not quoted strings). gtmux.set_option("X", Y) is the identical runtime
-- twin (same registry, same coercion); use it only for imperative set from a
-- bind/draw, not for static config like this.
gtmux.options.mouse = true
gtmux.options.mode_keys = "vi"

-- Command-prompt line editing (tmux: set -g status-keys vi). vi can't be modal
-- in gtmux (ESC cancels the prompt); use "emacs" if you want the C-u/C-w kill keys.
gtmux.options.status_keys = "vi"

-- System clipboard on copy-mode yank via OSC 52 (tmux: set -g set-clipboard on).
gtmux.options.set_clipboard = "on"

-- Longer status-left cap (tmux: set -g status-left-length 150).
-- NOTE: numeric option values need the upgraded binary (the old applyOpts had no
-- number case and silently dropped them). Kept as strings here so a not-yet-
-- upgraded server keeps the value; drop the quotes on the 3 numbers below (this,
-- copy_wheel_lines, status_interval) once the running server is upgraded.
gtmux.options.status_left_length = "150"

-- Copy-mode mouse (tmux copy-mode-vi: WheelUp/Down send -N5 -X scroll, and
-- unbind MouseDragEnd1Pane so a drag-release keeps the selection instead of
-- yanking + exiting).
gtmux.options.copy_wheel_lines = "5"
gtmux.options.copy_drag_finish = false

-- Pane borders: "simple" (straight │/─, tmux-faithful), "joined" (box-drawing
-- junctions where dividers cross), "framed" (every pane enclosed, content
-- shrinks 1 cell per side). rounded → ╭╮╰╯ corners.
gtmux.options.pane_borders = "framed"
gtmux.options.pane_border_rounded = true

-- Colours are ANSI names, so the terminal palette swaps under them. In light
-- themes every one of the 16 names is dark, so chrome goes "default" — the
-- terminal's own fg/bg. ~/.theme-mode is written by theme-apply.
-- pcall: a failure here must not abort the rest of this file.
local light = false
pcall(function()
    local f = io.open(os.getenv("HOME") .. "/.theme-mode")
    if f then light = (f:read("*l") == "light"); f:close() end
end)
gtmux.options.status_fg = light and "default" or "white"
gtmux.options.status_bg = light and "default" or "dark_grey"

gtmux.options.active_window_fg = light and "blue" or "black"
gtmux.options.active_window_bg = light and "default" or "green"

gtmux.options.active_border_fg = "magenta"
gtmux.options.marked_border_fg = "magenta"
gtmux.options.fill_fg = "dark_grey"

gtmux.options.copy_cursor_fg = "black"
gtmux.options.copy_cursor_bg = "yellow"
gtmux.options.copy_selection_fg = "black"
gtmux.options.copy_selection_bg = "light_cyan"

-- Status bar, matching tmux: status-left "[#h][#S]|", status-right the git
-- branch of the active pane's cwd (built-in #{git_branch} var replaces the
-- tmux #() shell snippet).
gtmux.options.status_left = "[#{host}][#{session}]|"
gtmux.options.status_right = "#{?git_branch,[git:#{git_branch}] ,}"
gtmux.options.status_interval = "15" -- string until upgrade (see note above)

-- Terminal title = session name (tmux: set-titles on / set-titles-string '#S')
gtmux.options.set_titles = true
gtmux.options.set_titles_string = "#{session}"

-- Negotiate kitty keyboard protocol (tmux: set -g extended-keys always)
gtmux.options.extended_keys = "always"

gtmux.options.prefix = "C-b"

-- Nullary verbs pass straight to bind (no wrapper closure needed); only binds
-- that pass an argument keep a `function() ... end`.
gtmux.bind("c", gtmux.new_window) -- opens in active pane's cwd
gtmux.bind("n", gtmux.next_window)
gtmux.bind("p", gtmux.prev_window)
gtmux.bind("x", gtmux.kill_pane)
gtmux.bind("d", gtmux.detach)
gtmux.bind("q", gtmux.show_pane_numbers)
gtmux.bind("$", gtmux.rename_session_prompt)
gtmux.bind(",", gtmux.rename_window_prompt)
gtmux.bind("z", gtmux.zoom)
gtmux.bind("{", function() gtmux.swap_pane("prev") end)
gtmux.bind("}", function() gtmux.swap_pane("next") end)
gtmux.bind("<", function() gtmux.swap_window("prev") end)
gtmux.bind(">", function() gtmux.swap_window("next") end)
gtmux.bind("!", gtmux.break_pane)
gtmux.bind("w", gtmux.choose_window)
gtmux.bind("s", gtmux.choose_session) -- tmux: choose-tree -Zs
gtmux.bind(":", gtmux.command_prompt)
gtmux.bind("[", gtmux.enter_copy_mode)
gtmux.bind("]", gtmux.paste)

-- Jump to the last session (tmux: bind b switch-client -l).
gtmux.bind("b", function() gtmux.switch_client("-l") end)

-- Workspacer: prompt for args, open a window running it (tmux's bind P). The
-- quoted nested command now survives; %1..%3 are the prompt answers.
gtmux.bind("P", function()
	gtmux.command_prompt("Workspacer args:", "", "new-window 'workspacer -W=current %1 %2 %3 ; read'")
end)

-- Workspacer session tree (tmux's bind S). gtmux evaluates the -f filter per
-- session via its format engine, but gtmux config is global and doesn't know
-- the active workspace — the prefix has to come from a user option the
-- workspacer gtmux-backend sets (e.g. @workspace_prefix). Until that's wired,
-- S shows the full tree; swap in the filtered line once the backend exports it.
gtmux.bind("S", gtmux.choose_tree)
-- gtmux.bind("S", function() gtmux.choose_tree("-f", "#{m:#{@workspace_prefix}-*,#{session_name}}") end)

-- Splits with | and - (new panes already open in the active pane's cwd,
-- tmux's -c "#{pane_current_path}"). % and " are unbound, like the tmux conf.
-- split_right/split_down are the clearer names; `or` falls back to the old
-- split_v/split_h so this line doesn't abort the file on a not-yet-upgraded server.
gtmux.bind("|", gtmux.split_right or gtmux.split_v) -- new pane to the right
gtmux.bind("-", gtmux.split_down or gtmux.split_h)  -- new pane below

-- Reload config (tmux: bind r source-file ~/.tmux.conf)
gtmux.bind("r", gtmux.source_file)

-- Kill the session after confirming (tmux: bind Q confirm-before kill-session)
gtmux.bind("Q", function() gtmux.confirm_before("kill-session", "kill-session? (y/n)") end)

-- Directional pane resize, repeatable (tmux's bind -r): 2 cells on h/j/k/l,
-- 10 on H/J/K/L, zoom on m.
gtmux.bind_repeat("h", function() gtmux.resize_pane("left", 2) end)
gtmux.bind_repeat("l", function() gtmux.resize_pane("right", 2) end)
gtmux.bind_repeat("k", function() gtmux.resize_pane("up", 2) end)
gtmux.bind_repeat("j", function() gtmux.resize_pane("down", 2) end)
gtmux.bind_repeat("H", function() gtmux.resize_pane("left", 10) end)
gtmux.bind_repeat("L", function() gtmux.resize_pane("right", 10) end)
gtmux.bind_repeat("K", function() gtmux.resize_pane("up", 10) end)
gtmux.bind_repeat("J", function() gtmux.resize_pane("down", 10) end)
gtmux.bind_repeat("m", gtmux.zoom)

-- Closest stand-in for the tmux join-pane picker binds (u/U/g): mark the pane
-- to move with prefix+M, then prefix+g in the destination window joins it.
gtmux.bind("M", gtmux.mark_pane)
gtmux.bind("g", gtmux.join_marked)

-- Jump to a window by number: prefix then the digit. (tmux's no-prefix
-- C-1..9 isn't possible — terminals emit no distinct byte for Ctrl+digit.)
for i = 1, 9 do
	gtmux.bind(tostring(i), function() gtmux.select_window(i) end)
end

-- Vim-aware pane navigation, no prefix (tmux's vim-split pattern). If the
-- focused pane runs vim the ctrl key is delivered to vim; otherwise it moves
-- between gtmux panes. C-\ selects the previously-active pane.
gtmux.bind_root("C-h", function() gtmux.select_pane_vim("left") end)
gtmux.bind_root("C-j", function() gtmux.select_pane_vim("down") end)
gtmux.bind_root("C-k", function() gtmux.select_pane_vim("up") end)
gtmux.bind_root("C-l", function() gtmux.select_pane_vim("right") end)
gtmux.bind_root("C-\\", function() gtmux.select_pane_vim("last") end)

gtmux.bind_root("C-1", function() gtmux.select_window(1) end)
gtmux.bind_root("C-2", function() gtmux.select_window(2) end)
gtmux.bind_root("C-3", function() gtmux.select_window(3) end)

-- Sidebar: bundled dock widget (SESSIONS list + Clanker agent panes; click a
-- row to jump there). Options: see `require("gtmux.sidebar")` in the gtmux
-- default config. prefix+B toggles it (below).
require("gtmux.sidebar"){ size = 25, min_cols = 110 }

-- Responsive: below 90 cols keep the active pane maximized (phone attach);
-- Tab cycles panes keeping the zoom. prefix+B force-shows/hides the sidebar
-- over its min_cols breakpoint.
gtmux.responsive{ cols_below = 90 }
gtmux.bind("Tab", gtmux.next_pane)
gtmux.bind("B", function() gtmux.toggle_dock("sidebar") end)
