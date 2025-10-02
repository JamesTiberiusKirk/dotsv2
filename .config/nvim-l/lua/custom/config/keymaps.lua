-- [[ Basic Keymaps ]]

-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>E', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })


vim.keymap.set(
  "n",
  "<leader>d",
  "<cmd>b#<bar>bd#<CR>",
  { noremap = true, silent = true, desc = "Close current buffer without closing pane" }
)
vim.keymap.set(
  "n",
  "<leader>D",
  "<cmd>b#<bar>bd!#<CR>",
  { noremap = true, silent = true, desc = "Force quit current buffer without closing pane" }
)
vim.keymap.set(
  "n",
  "<leader>rr",
  "<cmd>LspRestart<CR>",
  { noremap = true, silent = true, desc = "Restart the lsp" }
)

vim.keymap.set("v", "(", "di()<Esc>hp", { noremap = true, silent = true, desc = "Sorround with ()" })
vim.keymap.set("v", "[", "di[]<Esc>hp", { noremap = true, silent = true, desc = "Sorround with ()" })
vim.keymap.set("v", "{", "di{}<Esc>hp", { noremap = true, silent = true, desc = "Sorround with ()" })
vim.keymap.set("v", "'", "di''<Esc>hp", { noremap = true, silent = true, desc = "Sorround with ()" })
vim.keymap.set("v", '"', 'di""<Esc>hp', { noremap = true, silent = true, desc = "Sorround with ()" })
vim.keymap.set("v", "`", "di``<Esc>hp", { noremap = true, silent = true, desc = "Sorround with ()" })


vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true, desc = "Indent" })
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true, desc = "De-Indent" })

-- Clear highlighting
vim.keymap.set("n", "<leader><ESC>", "<cmd>noh<cr>", { noremap = true, silent = true, desc = "Clear highlighting" })


-- TABS
vim.keymap.set("n", "{", "<cmd>tabprevious<cr>", { noremap = true, silent = true, desc = "Tab previous" })
vim.keymap.set("n", "}", "<cmd>tabnext<cr>", { noremap = true, silent = true, desc = "Tab next" })



-- Window resize mode (i3-style): enter with <leader>wr
vim.keymap.set(
  'n',
  '<leader>wr',
  function() require('custom.resize_mode').toggle({ amount = 3 }) end,
  { noremap = true, silent = true, desc = 'Toggle resize mode' }
)
