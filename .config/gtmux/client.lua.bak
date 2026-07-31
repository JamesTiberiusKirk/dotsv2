-- gtmux client config: chrome colors and toggles, applied per-attach.
-- Mirrors ~/.tmux.conf as closely as gtmux allows. Genuinely still missing:
-- no-prefix C-1..C-9 (terminals emit no distinct byte for Ctrl+digit); the
-- join-pane choose-window %% picker (use prefix+M then g, or join-pane -s/-t);
-- escape-time (N/A — no client-side ESC timer). Ceilings: status-keys vi is
-- plain typing (ESC cancels the prompt, so no modal editing — emacs gets the
-- C-u/C-w kill keys); choose-tree/choose-session pane preview is captured at
-- open, not live.

gtmux.options.mouse = true
gtmux.options.mode_keys = "vi"

-- Command-prompt line editing (tmux: set -g status-keys vi). vi can't be modal
-- in gtmux (ESC cancels the prompt); use "emacs" if you want the C-u/C-w kill keys.
gtmux.set_option("status_keys", "vi")

-- System clipboard on copy-mode yank via OSC 52 (tmux: set -g set-clipboard on).
gtmux.set_option("set_clipboard", "on")

-- Longer status-left cap (tmux: set -g status-left-length 150).
gtmux.set_option("status_left_length", "150")

-- Copy-mode mouse (tmux copy-mode-vi: WheelUp/Down send -N5 -X scroll, and
-- unbind MouseDragEnd1Pane so a drag-release keeps the selection instead of
-- yanking + exiting).
gtmux.set_option("copy_wheel_lines", "5")
gtmux.set_option("copy_drag_finish", "false")

gtmux.options.status_fg = "white"
gtmux.options.status_bg = "dark_grey"

gtmux.options.active_window_fg = "black"
gtmux.options.active_window_bg = "green"

gtmux.options.active_border_fg = "green"
gtmux.options.marked_border_fg = "magenta"
gtmux.options.fill_fg = "dark_grey"

gtmux.options.copy_cursor_fg = "black"
gtmux.options.copy_cursor_bg = "yellow"
gtmux.options.copy_selection_fg = "black"
gtmux.options.copy_selection_bg = "light_cyan"

-- Status bar, matching tmux: status-left "[#h][#S]|", status-right the git
-- branch of the active pane's cwd (built-in #{git_branch} var replaces the
-- tmux #() shell snippet).
gtmux.set_option("status_left", "[#{host}][#{session}]|")
gtmux.set_option("status_right", "#{?git_branch,[git:#{git_branch}] ,}")
gtmux.set_option("status_interval", "15")

-- Terminal title = session name (tmux: set-titles on / set-titles-string '#S')
gtmux.set_option("set_titles", "true")
gtmux.set_option("set_titles_string", "#{session}")

-- Negotiate kitty keyboard protocol (tmux: set -g extended-keys always)
gtmux.set_option("extended_keys", "always")

gtmux.set_option("prefix", "C-b")

gtmux.bind("c", function() gtmux.new_window() end) -- opens in active pane's cwd
gtmux.bind("n", function() gtmux.next_window() end)
gtmux.bind("p", function() gtmux.prev_window() end)
gtmux.bind("x", function() gtmux.kill_pane() end)
gtmux.bind("d", function() gtmux.detach() end)
gtmux.bind("q", function() gtmux.show_pane_numbers() end)
gtmux.bind("$", function() gtmux.rename_session_prompt() end)
gtmux.bind(",", function() gtmux.rename_window_prompt() end)
gtmux.bind("z", function() gtmux.zoom() end)
gtmux.bind("{", function() gtmux.swap_pane("prev") end)
gtmux.bind("}", function() gtmux.swap_pane("next") end)
gtmux.bind("<", function() gtmux.swap_window("prev") end)
gtmux.bind(">", function() gtmux.swap_window("next") end)
gtmux.bind("!", function() gtmux.break_pane() end)
gtmux.bind("w", function() gtmux.choose_window() end)
gtmux.bind("s", function() gtmux.choose_session() end) -- tmux: choose-tree -Zs
gtmux.bind(":", function() gtmux.command_prompt() end)
gtmux.bind("[", function() gtmux.enter_copy_mode() end)
gtmux.bind("]", function() gtmux.paste() end)

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
gtmux.bind("S", function() gtmux.choose_tree() end)
-- gtmux.bind("S", function() gtmux.choose_tree("-f", "#{m:#{@workspace_prefix}-*,#{session_name}}") end)

-- Splits with | and - (new panes already open in the active pane's cwd,
-- tmux's -c "#{pane_current_path}"). % and " are unbound, like the tmux conf.
gtmux.bind("|", function() gtmux.split_v() end)
gtmux.bind("-", function() gtmux.split_h() end)

-- Reload config (tmux: bind r source-file ~/.tmux.conf)
gtmux.bind("r", function() gtmux.source_file() end)

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
gtmux.bind_repeat("m", function() gtmux.zoom() end)

-- Closest stand-in for the tmux join-pane picker binds (u/U/g): mark the pane
-- to move with prefix+M, then prefix+g in the destination window joins it.
gtmux.bind("M", function() gtmux.mark_pane() end)
gtmux.bind("g", function() gtmux.join_marked() end)

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

-- Drawn dashboard panel (canvas draw API): a bordered left dock with a live
-- SESSIONS list (current highlighted, click to switch) and a CLAUDE section
-- (every pane running `claude` across all sessions). Click any row naming a
-- session to jump there.
gtmux.widget{ dock = "left", size = 15, fg = "white", bg = "black", interval = 1,
  draw = function(c)
    c:box(0, 0, c.w, c.h, "fg=cyan,rounded")
    c:text(2, 0, " gtmux ", "fg=cyan,bold")

    c:text(2, 1, "SESSIONS", "fg=cyan,bold")
    local cur, y = gtmux.context().session, 2
    for _, s in ipairs(gtmux.sessions()) do
      local here = (s.name == cur)
      c:text(2, y, (here and "> " or "  ") .. s.name .. "(" .. s.windows .. ")",
             here and "fg=green,bold" or "fg=white")
      y = y + 1
    end

    c:hline(y, "fg=dark_grey"); y = y + 1
    c:text(2, y, "Clanker", "fg=magenta,bold"); y = y + 1
    local hits = gtmux.find_panes({ command = "claude" })
    if #hits == 0 then
      c:text(2, y, "(none)", "fg=dark_grey")
    else
      for _, p in ipairs(hits) do
        c:text(2, y, p.session .. ":" .. p.window .. "." .. p.number, "fg=magenta")
        y = y + 1
      end
    end
  end,
  on_click = function(hit)
    -- switch to whichever session name appears on the clicked row
    for _, s in ipairs(gtmux.sessions()) do
      if hit.line_text:find(s.name, 1, true) then
        gtmux.switch_session(s.name); return
      end
    end
  end }
