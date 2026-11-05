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
gtmux.options.copy_line_numbers = "relative"

-- Command-prompt line editing (tmux: set -g status-keys vi). vi can't be modal
-- in gtmux (ESC cancels the prompt); use "emacs" if you want the C-u/C-w kill keys.
gtmux.options.status_keys = "vi"

-- System clipboard on copy-mode yank via OSC 52 (tmux: set -g set-clipboard on).
gtmux.options.set_clipboard = "on"


-- Copy-mode mouse (tmux copy-mode-vi: WheelUp/Down send -N5 -X scroll, and
-- unbind MouseDragEnd1Pane so a drag-release keeps the selection instead of
-- yanking + exiting).
gtmux.options.copy_wheel_lines = 5
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

-- The status bar is the default component (transparent: ● session, window
-- list, branch · host · clock) copied from gtmux's default_client.lua, plus a
-- ping segment. Its accent is active_border_fg above. Re-sync with upstream
-- by diffing against `gtmux init-config` output if gtmux's default changes.
gtmux.options.status_interval = 15

-- Ping: #client() runs synchronously and is cached for status_interval, so the
-- timeout must stay short. Hard deadline so ping always exits within 1s, even
-- if it never gets a reply: -t on macOS, -w on Linux (-W only caps the reply wait).
local ping_deadline = "-w1"
pcall(function()
    local p = io.popen("uname")
    if p then
        if p:read("*l") == "Darwin" then ping_deadline = "-t1" end
        p:close()
    end
end)
-- No parens in the command: #client(...) matches the closing paren.
local PING_CMD = "#client(ping -c1 " .. ping_deadline ..
    " 1.1.1.1 2>/dev/null | grep -o 'time=[0-9.]*' | cut -d= -f2)"

gtmux.widget{ dock = "status", component = function(props, ui)
  local accent = "fg=" .. (gtmux.options.active_border_fg or "green")
  local DIM = "fg=dark_grey"
  -- display width in cells: count UTF-8 lead bytes (# counts bytes, and ●/⤢/·
  -- are 3 bytes each)
  local function len(s) return (select(2, s:gsub("[^\128-\191]", ""))) end
  local x = 1
  local function put(s, style) ui:text(x, 0, s, style); x = x + len(s) end

  put("●", accent)
  x = x + 1
  put(gtmux.expand("#{session}"), accent .. ",bold")
  x = x + 3
  for _, w in ipairs(gtmux.windows()) do
    local mark = ""
    if w.flags:find("Z", 1, true) then mark = " ⤢" end
    local alert = w.flags:find("[!#~]") ~= nil
    local label = w.index .. " " .. w.name .. mark
    local width = len(label) + (alert and 2 or 0)
    ui:child(x, 0, width, 1, function(p, cell)
      cell:text(0, 0, p.idx .. "", p.active and (p.accent .. ",bold") or p.dim)
      cell:text(len(p.idx .. "") + 1, 0, p.rest, p.active and "fg=default,bold" or p.dim)
      if p.alert then cell:text(p.width - 1, 0, "•", "fg=red,bold") end
      cell:on_click(function() gtmux.select_window(p.idx) end)
    end, { idx = w.index, rest = w.name .. mark, active = w.active, alert = alert,
           width = width, accent = accent, dim = DIM })
    x = x + width + 3
  end

  local parts = {}
  local branch = gtmux.expand("#{git_branch}")
  if branch ~= "" then parts[#parts + 1] = "⎇ " .. branch end
  parts[#parts + 1] = gtmux.expand("#{host}")
  local right = table.concat(parts, " · ")
  local clock = gtmux.expand("#{clock}")

  -- ping, just left of the clock: green under 150ms, yellow above, red when unreachable
  local ms = tonumber(gtmux.expand(PING_CMD))
  local ptxt, pstyle = "✗", "fg=red"
  if ms then
    ptxt = string.format("%dms", ms + 0.5)
    pstyle = ms < 150 and "fg=green" or "fg=yellow"
  end
  local rx = ui.w - len(right) - 3 - len(ptxt) - 3 - len(clock) - 1
  ui:text(rx, 0, right .. " · ", DIM)
  ui:text(rx + len(right) + 3, 0, ptxt, pstyle)
  ui:text(rx + len(right) + 3 + len(ptxt), 0, " · " .. clock, DIM)
end }

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
gtmux.bind("x", function() gtmux.confirm_before("kill-pane", "kill this pane?") end)
gtmux.bind("&", function() gtmux.confirm_before("kill-window", "kill this window?") end)
gtmux.bind("d", gtmux.detach)
gtmux.bind("q", function() gtmux.confirm_before("set-option detach-on-destroy off ; kill-session", "kill this session?") end)
gtmux.bind("$", gtmux.rename_session_prompt)
gtmux.bind(",", gtmux.rename_window_prompt)
gtmux.bind("z", gtmux.zoom)
gtmux.bind("{", function() gtmux.swap_pane("prev") end)
gtmux.bind("}", function() gtmux.swap_pane("next") end)
gtmux.bind("<", function() gtmux.swap_window("prev") end)
gtmux.bind(">", function() gtmux.swap_window("next") end)
gtmux.bind("!", gtmux.break_pane)
gtmux.bind("w", gtmux.choose_window)
-- prefix+s (fuzzy session finder) and prefix+: (command palette) come from
-- the default config.
gtmux.bind("[", gtmux.enter_copy_mode)
gtmux.bind("]", gtmux.paste)

-- Jump to the last session (tmux: bind b switch-client -l).
gtmux.bind("b", function() gtmux.switch_client("-l") end)

-- Workspacer: prompt for args, open a window running it (tmux's bind P). The
-- quoted nested command now survives; %1..%3 are the prompt answers.
gtmux.bind("P", function()
	gtmux.command_prompt("Workspacer args:", "", "new-window 'workspacer -W=current %1 %2 %3 ; read'")
end)

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
gtmux.bind_root("C-4", function() gtmux.select_window(4) end)
gtmux.bind_root("C-5", function() gtmux.select_window(5) end)
gtmux.bind_root("C-6", function() gtmux.select_window(6) end)
gtmux.bind_root("C-7", function() gtmux.select_window(7) end)
gtmux.bind_root("C-8", function() gtmux.select_window(8) end)
gtmux.bind_root("C-9", function() gtmux.select_window(9) end)

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
