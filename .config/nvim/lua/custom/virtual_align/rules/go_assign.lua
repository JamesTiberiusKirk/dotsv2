-- Rule: align the '=' of consecutive single-line assignments (=, :=, += ...).
--   variant.ID··········· = x
--   n··················· := y
--   variant.Reservations += z
local M = {}

local align = require('custom.virtual_align.align')
local query = vim.treesitter.query.parse('go', '[(assignment_statement) (short_var_declaration)] @a')

-- statements only; skips `if x := f(); ...` and for-clause headers
local in_body = { block = true, statement_list = true }

function M.render(buf, root, ns)
  local found = {}
  for _, node in query:iter_captures(root, buf) do
    local sr, _, er = node:range()
    local lhs = node:field('left')[1]
    if sr == er and lhs and in_body[node:parent():type()] then
      local _, _, _, lec = lhs:range()
      local text = vim.api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1]
      -- width up to the '=' of the operator, so :=, += and = all line up on the '='
      local eq = text:find('=', lec + 1, true)
      found[#found + 1] = { row = sr, indent = text:match('^%s*'), lhs_end = lec, width = vim.fn.strdisplaywidth(text:sub(1, eq - 1)) }
    end
  end
  table.sort(found, function(a, b)
    return a.row < b.row
  end)

  local groups, rows, prev = {}, {}, nil
  for _, f in ipairs(found) do
    if prev and (f.row ~= prev.row + 1 or f.indent ~= prev.indent) then
      groups[#groups + 1] = rows
      rows = {}
    end
    -- second cell is a dummy so align() pads the first (it never pads the last)
    rows[#rows + 1] = { { row = f.row, end_col = f.lhs_end, width = f.width }, { width = 0 } }
    prev = f
  end
  groups[#groups + 1] = rows
  align(buf, ns, groups)
end

return M
