-- Keep Go indent consistent and predictable
-- Adjust these if you prefer a different width

-- Go style uses tabs; keep tabs but show width 4
vim.opt_local.expandtab = false
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.softtabstop = 4

-- Guard against other plugins changing options on save
local grp = vim.api.nvim_create_augroup('GoIndentGuard', { clear = false })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
  group = grp,
  pattern = '*.go',
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.softtabstop = 4
  end,
})

