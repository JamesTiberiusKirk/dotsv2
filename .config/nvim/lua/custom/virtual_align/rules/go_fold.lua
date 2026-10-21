-- Rule: show short Go blocks on one line (GoLand-style folding). Unfolds while the cursor is inside.
--   if err != nil {        ->  if err != nil { return err }
--       return err
--   }
-- Covers: if with a single return/panic, functions with a single return, case clauses with one statement.
local M = {}

local HL = 'Comment'
local query = vim.treesitter.query.parse(
  'go',
  [[
  (if_statement) @if
  (function_declaration) @func
  (method_declaration) @func
  (func_literal) @func
  (expression_case) @case
  (type_case) @case
  (default_case) @case
]]
)

-- Named children, flattening statement_list (newer tree-sitter-go wraps statements in it).
-- Comments count as statements, so blocks with comments never fold.
local function statements(node, after_colon)
  local out, seen_colon = {}, not after_colon
  for c in node:iter_children() do
    if not c:named() and c:type() == ':' then
      seen_colon = true
    elseif seen_colon and c:named() then
      if c:type() == 'statement_list' then
        for s in c:iter_children() do
          if s:named() then
            out[#out + 1] = s
          end
        end
      else
        out[#out + 1] = c
      end
    end
  end
  return out
end

local function single_line(node)
  local sr, _, er = node:range()
  return sr == er
end

local function is_return_or_panic(stmt, buf)
  if stmt:type() == 'return_statement' then
    return true
  end
  local call = stmt:type() == 'expression_statement' and stmt:named_child(0)
  local fn = call and call:type() == 'call_expression' and call:field('function')[1]
  return fn and vim.treesitter.get_node_text(fn, buf) == 'panic'
end

local function line(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
end

local hlq = vim.treesitter.query.get('go', 'highlights')

-- Treesitter-coloured virt_text chunks for bytes [scol, ecol) of one row; appended to `out`.
-- ponytail: treesitter colours only, LSP semantic tokens are not copied
local function chunks(out, buf, root, row, scol, ecol)
  local text = line(buf, row)
  local hls = {}
  for id, node in hlq:iter_captures(root, buf, row, row + 1) do
    local name = hlq.captures[id]
    if name:sub(1, 1) ~= '_' and name ~= 'spell' and name ~= 'nospell' then
      local sr, sc, er, ec = node:range()
      local from = math.max(sr < row and 0 or sc, scol)
      local to = math.min(er > row and #text or ec, ecol)
      for b = from, to - 1 do
        hls[b] = '@' .. name .. '.go' -- later captures win, like the highlighter
      end
    end
  end
  local start = scol
  for b = scol + 1, ecol do
    if b == ecol or hls[b] ~= hls[start] then
      out[#out + 1] = { text:sub(start + 1, b), hls[start] }
      start = b
    end
  end
  return out
end

-- Draw `stmt` (and the closing line, if any) at the end of header_row and hide the lines below it.
-- Code keeps its colours; only the braces are dimmed to mark the fold.
local function fold(buf, root, ns, header_row, stmt, close_row)
  local srow, scol, _, ecol = stmt:range()
  if srow ~= header_row + 1 or not single_line(stmt) then
    return
  end
  local virt = chunks({ { ' ' } }, buf, root, srow, scol, ecol)
  local header = line(buf, header_row)
  if close_row then
    if close_row ~= srow + 1 then
      return
    end
    local close = line(buf, close_row)
    local brace = close:find('}') -- closing line always starts with }
    virt[#virt + 1] = { ' ' }
    virt[#virt + 1] = { '}', HL }
    chunks(virt, buf, root, close_row, brace, #close)
    local open = #header:gsub('%s+$', '')
    if header:sub(open, open) == '{' then
      vim.api.nvim_buf_set_extmark(buf, ns, header_row, open - 1, { end_col = open, hl_group = HL })
    end
  end
  local last = close_row or srow
  vim.api.nvim_buf_set_extmark(buf, ns, header_row, #header, {
    virt_text = virt,
    virt_text_pos = 'inline',
  })
  for r = header_row + 1, last do
    vim.api.nvim_buf_set_extmark(buf, ns, r, 0, { conceal_lines = '' })
  end
end

-- Fold a `{ ... }` block holding exactly one statement that passes `ok`.
local function fold_block(buf, root, ns, block, ok)
  local stmts = block and statements(block)
  if not stmts or #stmts ~= 1 or not ok(stmts[1]) then
    return
  end
  local br, _, ber = block:range()
  fold(buf, root, ns, br, stmts[1], ber)
end

function M.render(buf, root, ns)
  local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)[1] - 1 or -1
  for id, node in query:iter_captures(root, buf) do
    local sr, _, er = node:range()
    if cursor < sr or cursor > er then
      local kind = query.captures[id]
      if kind == 'if' and not node:field('alternative')[1] then
        fold_block(buf, root, ns, node:field('consequence')[1], function(s)
          return is_return_or_panic(s, buf)
        end)
      elseif kind == 'func' then
        fold_block(buf, root, ns, node:field('body')[1], function(s)
          return s:type() == 'return_statement'
        end)
      elseif kind == 'case' and vim.trim(line(buf, sr)):sub(-1) == ':' then
        local stmts = statements(node, true)
        if #stmts == 1 then
          fold(buf, root, ns, sr, stmts[1])
        end
      end
    end
  end
end

return M
