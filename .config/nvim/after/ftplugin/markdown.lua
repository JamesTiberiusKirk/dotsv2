-- Ensure Markdown buffers wrap lines nicely
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.breakindent = true
vim.opt_local.textwidth = 0 -- avoid hard wrapping
vim.opt_local.colorcolumn = ''

-- Guard against plugins flipping wrap off after opening
local grp = vim.api.nvim_create_augroup('MarkdownWrapGuard', { clear = false })
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter' }, {
  group = grp,
  buffer = 0,
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
  end,
})

