-- Display-only code presentation: draws extmarks, never edits the buffer.
-- Add a rule: create rules/<name>.lua exposing render(buf, root, ns), then list it under its filetype below.
local M = {}

local ns = vim.api.nvim_create_namespace('virtual_align')
local enabled = true

-- filetype -> { rule module names under custom.virtual_align.rules }
local rules_by_ft = {
  go = { 'go_tags', 'go_fold', 'go_assign' },
}

function M.render(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local names = rules_by_ft[vim.bo[buf].filetype]
  if not enabled or not names then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return
  end
  local root = parser:parse()[1]:root()
  for _, name in ipairs(names) do
    require('custom.virtual_align.rules.' .. name).render(buf, root, ns)
  end
end

function M.toggle()
  enabled = not enabled
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.render(buf)
    end
  end
  vim.notify('virtual align ' .. (enabled and 'on' or 'off'))
end

function M.setup()
  -- ponytail: full re-render on every CursorMoved (folds unfold under the cursor); fine for normal file sizes, scope to visible range if it lags
  vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter', 'TextChanged', 'InsertLeave', 'CursorMoved' }, {
    group = vim.api.nvim_create_augroup('VirtualAlign', { clear = true }),
    callback = function(a)
      if rules_by_ft[vim.bo[a.buf].filetype] then
        M.render(a.buf)
      end
    end,
  })
  vim.api.nvim_create_user_command('VirtualAlignToggle', M.toggle, {})
end

return M
