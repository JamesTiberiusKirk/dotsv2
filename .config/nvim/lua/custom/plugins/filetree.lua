-- Unless you are still migrating, remove the deprecated commands from v1.x
vim.cmd [[ let g:neo_tree_remove_legacy_commands = 1 ]]

-- ponytail: nowrap clips long names off-screen but the full path is still
-- known to neo-tree's tree state; float it next to the tree on demand (K,
-- matching the LSP hover keymap) instead of widening the window
local hover_win = nil
local function close_hover()
  if hover_win and vim.api.nvim_win_is_valid(hover_win) then
    vim.api.nvim_win_close(hover_win, true)
  end
  hover_win = nil
end

local function show_hover(state)
  close_hover()
  local node = state.tree:get_node()
  local text = node and node.path and vim.fn.fnamemodify(node.path, ":.")
  if not text or text == "" then
    return
  end
  local win = state.winid
  local win_width = vim.api.nvim_win_get_width(win)
  local win_pos = vim.api.nvim_win_get_position(win)
  local row = win_pos[1] + vim.fn.winline() - 1
  local col = win_pos[2] + win_width

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  hover_win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = vim.fn.strdisplaywidth(text) + 2,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
  })
end

local function yank_relative_path(state)
  local node = state.tree:get_node()
  local text = node and node.path and vim.fn.fnamemodify(node.path, ":.")
  if not text or text == "" then
    return
  end
  vim.fn.setreg("+", text)
end

return {
  {
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
      "MunifTanjim/nui.nvim",
      -- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
    },
    "nvim-neo-tree/neo-tree.nvim",
    cmd = "Neotree",
    lazy = false,
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Explorer NeoTree (root dir)", remap = true },
    },
    deactivate = function()
      vim.cmd([[Neotree close]])
    end,
    init = function()
      vim.g.neo_tree_remove_legacy_commands = 1
      if vim.fn.argc() == 1 then
        local stat = vim.loop.fs_stat(vim.fn.argv(0))
        if stat and stat.type == "directory" then
          require("neo-tree")
        end
      end

      local group = vim.api.nvim_create_augroup("neo_tree_hover", { clear = true })
      vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "WinLeave" }, {
        group = group,
        callback = close_hover,
      })
    end,
    opts = {
      buffers = {
        follow_current_file = {
          enabled = true, -- This will find and focus the file in the active buffer every time
          --              -- the current file is changed while the tree is open.
          leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
        },
      },
      filesystem = {
        follow_current_file = {
          enabled = true, -- This will find and focus the file in the active buffer every time
          --              -- the current file is changed while the tree is open.
          leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
        },
        filtered_items = {
          bind_to_cwd = false,
          follow_current_file = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
        window = {
          mappings = {
            ["<space>"] = "none",
            ["K"] = show_hover,
            ["Y"] = yank_relative_path,
          },
        },
      },
    },
  },
}
