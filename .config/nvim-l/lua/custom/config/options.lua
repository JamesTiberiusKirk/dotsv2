-- Some basics

-- Set highlight on search
vim.o.hlsearch = true

-- Make line numbers default
vim.wo.number = true

-- Enable mouse mode
vim.o.mouse = 'a'

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.o.clipboard = 'unnamedplus'

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'
-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300
-- Set completeopt to have a better completion experience
-- vim.o.completeopt = 'menuone,noselect'
vim.o.termguicolors = true
vim.wo.relativenumber = true



-- Usefull for debugging the lsp
-- vim.cmd([[
--   let g:go_debug=['lsp']
-- ]])

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.cmd([[ 
  set softtabstop=4
  set tabstop=4
  set shiftwidth=4
  set expandtab
  set conceallevel=0
  set spell

  autocmd FileType neoterm setlocal spell nospell
]])


