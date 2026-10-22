-- Rule: align struct tag pairs (bson/json/...) across fields of a Go struct.
local M = {}

local align = require('custom.virtual_align.align')
local query = vim.treesitter.query.parse('go', '(field_declaration_list) @list')

function M.render(buf, root, ns)
  local groups = {}
  for _, list in query:iter_captures(root, buf) do
    local rows = {}
    local prev_end
    for field in list:iter_children() do
      -- gofmt restarts alignment after a blank line or own-line comment
      local fr, _, fer = field:range()
      local own_line_comment = field:type() == 'comment' and prev_end and fr > prev_end
      if prev_end and (fr - prev_end > 1 or own_line_comment) then
        groups[#groups + 1] = rows
        rows = {}
      end
      prev_end = fer
      local tag = field:type() == 'field_declaration' and field:field('tag')[1]
      if tag then
        local sr, sc, er = tag:range()
        local text = vim.treesitter.get_node_text(tag, buf)
        -- single-line raw strings only: `k:"v" k2:"v2"`
        if sr == er and text:sub(1, 1) == '`' then
          local cells = {}
          for p, e in text:gmatch('(%w+:"[^"]*")()') do
            cells[#cells + 1] = { row = sr, end_col = sc + e - 1, width = vim.fn.strdisplaywidth(p) }
          end
          rows[#rows + 1] = cells
        end
      end
    end
    groups[#groups + 1] = rows
  end
  align(buf, ns, groups)
end

return M
