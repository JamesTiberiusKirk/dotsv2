-- Helper for alignment rules: pads cell N to the same width across all rows of a group.
-- groups = { rows }, rows = { cells }, cell = { row, end_col, width }
local FILL = '·'
local HL = 'Comment'

return function(buf, ns, groups)
  for _, rows in ipairs(groups) do
    local widths = {}
    for _, cells in ipairs(rows) do
      for i, c in ipairs(cells) do
        widths[i] = math.max(widths[i] or 0, c.width)
      end
    end
    for _, cells in ipairs(rows) do
      for i, c in ipairs(cells) do
        local pad = widths[i] - c.width
        -- last cell in a row needs no padding
        if pad > 0 and i < #cells then
          vim.api.nvim_buf_set_extmark(buf, ns, c.row, c.end_col, {
            virt_text = { { string.rep(FILL, pad), HL } },
            virt_text_pos = 'inline',
          })
        end
      end
    end
  end
end
