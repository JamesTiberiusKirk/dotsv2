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

-- Pane borders: "simple" (straight │/─, tmux-faithful), "joined" (box-drawing
-- junctions where dividers cross), "framed" (every pane enclosed, content
-- shrinks 1 cell per side). rounded → ╭╮╰╯ corners.
gtmux.options.pane_borders = "framed"
gtmux.options.pane_border_rounded = true

gtmux.options.status_fg = "white"
gtmux.options.status_bg = "dark_grey"

gtmux.options.active_window_fg = "black"
gtmux.options.active_window_bg = "green"

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

gtmux.bind_root("C-1", function() gtmux.select_window(1) end)
gtmux.bind_root("C-2", function() gtmux.select_window(2) end)
gtmux.bind_root("C-3", function() gtmux.select_window(3) end)

-- Drawn dashboard panel (canvas draw API): a bordered left dock with a live
-- SESSIONS list (current highlighted, click to switch) and a Clanker section
-- (every pane running an agent — claude/codex/opencode — across all sessions),
-- coloured by whether the agent is working or awaiting your input. Click any
-- row naming a session to jump there.
--
-- Clanker display toggles (edit to taste):
local CLANKER_SPINNER = true   -- animate a spinner glyph on working agents
local CLANKER_TITLE   = true   -- show the agent's current task title
-- Per-pane "you've seen it" state + the spinner animation frame, kept in
-- upvalues so they persist across the 1s redraws. dismissed[id]=true means an
-- idle agent has been focused since it last stopped (→ grey, not red); it's
-- re-armed whenever the agent goes back to work.
local clankerDismissed = {}
local clankerFrame = 0
local clankerSpin = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
gtmux.widget{ dock = "left", size = 25, fg = "white", bg = "", interval = 1,
  name = "sidebar", min_cols = 110, -- auto-hide on narrow clients; prefix+B toggles
  draw = function(c)
    -- box returns its interior as a clipped child: text drawn through `inner`
    -- is truncated at the border instead of overwriting it. The title and the
    -- hline stay on `c` on purpose — the title sits ON the top border row, and
    -- hline spans the full width so it merges into the sides as tees.
    local inner = c:box(0, 0, c.w, c.h, "fg=cyan,rounded")
    c:text(2, 0, " gtmux ", "fg=cyan,bold")

    inner:text(1, 0, "SESSIONS", "fg=cyan,bold")
    local cur, y = gtmux.context().session, 2   -- y stays in PARENT coords
    for _, s in ipairs(gtmux.sessions()) do
      local here = (s.name == cur)
      inner:text(1, y - 1, (here and "> " or "  ") .. s.name,
             here and "fg=green,bold" or "fg=white")
      y = y + 1
    end

    c:hline(y, "fg=dark_grey"); y = y + 1
    inner:text(1, y - 1, "Clanker", "fg=magenta,bold"); y = y + 1
    -- State comes from the OSC-0 title: claude & codex put a braille spinner
    -- (UTF-8 E2 A0-A3 xx, the U+2800 block) in the title while working and drop
    -- it when they stop for you — so no spinner = awaiting input. opencode sets
    -- no title, so its state is unknown (?).
    clankerFrame = clankerFrame + 1
    local focused = gtmux.context().pane
    local tags = { claude = "cl", codex = "cx", opencode = "oc" }
    local shown = 0
    for _, p in ipairs(gtmux.find_panes({})) do
      local tag = tags[p.command]
      if tag then
        local glyph, style
        if p.command == "opencode" or p.title == "" then
          glyph, style = "?", "fg=magenta"                    -- state unknown
        elseif p.title:find("\226[\160-\163]") then           -- spinner = working
          clankerDismissed[p.id] = nil                        -- re-arm for next idle
          glyph = CLANKER_SPINNER and clankerSpin[(clankerFrame % #clankerSpin) + 1] or "~"
          style = "fg=blue"
        else                                                  -- no spinner = idle
          if focused == ("%" .. p.id) then clankerDismissed[p.id] = true end
          if clankerDismissed[p.id] then
            glyph, style = "·", "fg=dark_grey"                -- seen it → dismissed
          else
            glyph, style = "!", "fg=red,bold"                 -- awaiting you
          end
        end
        local row = tag .. " " .. glyph .. " " .. p.session .. ":" .. p.window .. "." .. p.number
        if CLANKER_TITLE and glyph ~= "?" then
          local disp = p.title:match("[%w].*")                -- strip leading status glyph
          if disp and disp ~= "" then row = row .. " " .. disp end
        end
        inner:text(1, y - 1, row, style)
        y = y + 1; shown = shown + 1
      end
    end
    if shown == 0 then inner:text(1, y - 1, "(none)", "fg=dark_grey") end
  end,
  on_click = function(hit)
    -- switch to whichever session name appears on the clicked row
    for _, s in ipairs(gtmux.sessions()) do
      if hit.line_text:find(s.name, 1, true) then
        gtmux.switch_session(s.name); return
      end
    end
  end }

-- Responsive: below 90 cols keep the active pane maximized (phone attach);
-- Tab cycles panes keeping the zoom. prefix+B force-shows/hides the sidebar
-- over its min_cols breakpoint.
gtmux.responsive{ cols_below = 90 }
gtmux.bind("Tab", function() gtmux.next_pane() end)
gtmux.bind("B", function() gtmux.toggle_dock("sidebar") end)
