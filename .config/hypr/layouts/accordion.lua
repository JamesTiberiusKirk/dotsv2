-- Aerospace-style accordion, registered twice: accordion:horizontal and
-- accordion:vertical. Windows keep full (shared) size and overlap, each
-- shifted by a peek strip; the focused one sits on top.

-- Overlapping windows make hover-focus steal focus through the peek strips,
-- so hover is disabled while an accordion workspace is active.
-- ponytail: restore value 1 is hardcoded (matches base.lua); layouts load
-- before base so it can't be read from config here.
local function sync_follow_mouse()
    local ws = hl.get_active_workspace()
    local accordion = ws and ws.tiled_layout and ws.tiled_layout:find("lua:accordion", 1, true) == 1
    hl.config({ input = { follow_mouse = accordion and 3 or 1 } })
end

hl.on("workspace.active", sync_follow_mouse)

local function clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

-- Gaps are applied after placement: the first window's leading edge touches
-- the workarea (outer gap, +5) while the rest get the inner-gap treatment
-- (+10), which renders the first peek strip 5px fatter. Shift the followers
-- back by the difference so all strips are equal.
-- ponytail: hardcoded to gaps_in=5 from base.lua; the lua API has no
-- config getter to read it.
local GAP_FIX = 5

-- The outer gap adds ~5px of wallpaper before the first fold and after the
-- last one, so those folds read wider than the middle ones. Shrink them by
-- that amount so the visual rhythm (border to border, wallpaper to border)
-- is identical across all folds.
-- ponytail: hardcoded to gaps_out=5 from base.lua, same reason as GAP_FIX.
local EDGE_FIX = 5

local function focused_index(ctx)
    local focused = 1
    for i, target in ipairs(ctx.targets) do
        local w = target.window
        if w and w.active then
            focused = i
        end
    end
    return focused
end

-- Hyprland stacks by focus history, which buries the peek strips of windows
-- that were focused recently. Rebuild z-order outward from the focused
-- window: left stack raised in index order, right stack in reverse, focused
-- last (on top), so every strip stays visible.
local function restack(ctx)
    local n = #ctx.targets
    if n < 2 then
        return
    end

    local focused = focused_index(ctx)

    local function raise(i)
        local w = ctx.targets[i].window
        if w then
            hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:" .. w.address }))
        end
    end

    for i = 1, focused - 1 do raise(i) end
    for i = n, focused + 1, -1 do raise(i) end
    raise(focused)
end

local function register(name, dir)
    local state = { peek = 40 }

    hl.layout.register(name, {
        recalculate = function(ctx)
            local n = #ctx.targets
            if n == 0 then
                return
            end

            local area = ctx.area

            -- covers layout being switched on the already-active workspace,
            -- where no workspace.active event fires
            sync_follow_mouse()

            for i, target in ipairs(ctx.targets) do
                -- leading edge: everyone but the first sits off the workarea
                -- edge; trailing edge: everyone but the last does. Both get
                -- the inner-gap treatment there, so compensate to keep every
                -- reveal identical.
                local lead  = i > 1 and (GAP_FIX + EDGE_FIX) or 0
                local trail = i < n and (GAP_FIX + EDGE_FIX) or 0
                if dir == "h" then
                    target:place({
                        x = area.x + (i - 1) * state.peek - lead,
                        y = area.y,
                        w = area.w - (n - 1) * state.peek + lead + trail,
                        h = area.h,
                    })
                else
                    target:place({
                        x = area.x,
                        y = area.y + (i - 1) * state.peek - lead,
                        w = area.w,
                        h = area.h - (n - 1) * state.peek + lead + trail,
                    })
                end
            end

            restack(ctx)
        end,

        layout_msg = function(ctx, msg)
            local command, arg = msg:match("^(%S+)%s*(.*)$")

            if command == "peek" then
                state.peek = clamp(tonumber(arg) or state.peek, 5, 300)
            elseif command == "grow" then
                state.peek = clamp(state.peek + 10, 5, 300)
            elseif command == "shrink" then
                state.peek = clamp(state.peek - 10, 5, 300)
            elseif command == "focus" then
                -- Binds forward focus here so the layout owns navigation:
                -- keys on the accordion's axis walk the stack in target
                -- order (cycle_next walks focus history, which restack()
                -- reshuffles every keypress); cross-axis keys do nothing.
                local on_axis = (dir == "h" and (arg == "l" or arg == "r"))
                    or (dir == "v" and (arg == "u" or arg == "d"))
                local n = #ctx.targets
                if on_axis and n > 1 then
                    local step = (arg == "r" or arg == "d") and 1 or -1
                    local next_i = ((focused_index(ctx) - 1 + step) % n) + 1
                    local w = ctx.targets[next_i].window
                    if w then
                        hl.dispatch(hl.dsp.focus({ window = "address:" .. w.address }))
                    end
                    restack(ctx)
                end
            else
                return name .. ": expected peek <5..300>, grow, shrink, or focus <l|r|u|d>"
            end

            return true
        end,
    })
end

register("accordion:horizontal", "h")
register("accordion:vertical", "v")
