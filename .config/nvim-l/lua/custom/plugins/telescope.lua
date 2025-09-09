return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  version = false, -- telescope did only one release, so use HEAD for now
  dependencies = {
    {
      "benfowler/telescope-luasnip.nvim",
      config = function ()
        require('telescope').load_extension('luasnip')
      end
    },
    {"nvim-telescope/telescope-live-grep-args.nvim"},
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      enabled = vim.fn.executable("make") == 1,
      config = function()
        require("telescope").load_extension("fzf")
      end,
    },
    {
      "aaronhallaert/advanced-git-search.nvim",
      cmd = { "AdvancedGitSearch" },
      config = function()
        require("telescope").load_extension "advanced_git_search"
      end,
    },
    "tpope/vim-fugitive",
    -- to open commits in browser with fugitive
    "tpope/vim-rhubarb",
  },
  keys = {
    { "<leader>:", function() require('telescope.builtin').command_history() end, desc = "Command History" },
    -- lsp
    { "<leader>gr", function() require('telescope.builtin').lsp_references() end, desc = "LSP references" },
    -- find
    { "<leader>fb", function() require('telescope.builtin').buffers({ sort_mru = true, sort_lastused = true }) end, desc = "Buffers" },
    { "<leader>ff", function() require('telescope.builtin').find_files() end, desc = "Find Files (root dir)" },
    { "<leader>fr", function() require('telescope.builtin').oldfiles() end, desc = "Recent" },
    -- git
    { "<leader>gc", function() require('telescope.builtin').git_commits() end, desc = "commits" },
    { "<leader>gs", function() require('telescope.builtin').git_status() end, desc = "status" },
    -- search
    { '<leader>s"', function() require('telescope.builtin').registers() end, desc = "Registers" },
    { "<leader>sa", function() require('telescope.builtin').autocommands() end, desc = "Auto Commands" },
    { "<leader>sb", function() require('telescope.builtin').current_buffer_fuzzy_find() end, desc = "Buffer" },
    { "<leader>sc", function() require('telescope.builtin').command_history() end, desc = "Command History" },
    { "<leader>sC", function() require('telescope.builtin').commands() end, desc = "Commands" },
    { "<leader>sd", function() require('telescope.builtin').diagnostics({ bufnr = 0 }) end, desc = "Document diagnostics" },
    { "<leader>sD", function() require('telescope.builtin').diagnostics() end, desc = "Workspace diagnostics" },
    {
      "<leader>sg",
      function ()
        require('telescope').extensions.live_grep_args.live_grep_args()
      end,
      desc = "Grep with rg params",
    },
    { "<leader>sh", function() require('telescope.builtin').help_tags() end, desc = "Help Pages" },
    { "<leader>sH", function() require('telescope.builtin').highlights() end, desc = "Search Highlight Groups" },
    { "<leader>sk", function() require('telescope.builtin').keymaps() end, desc = "Key Maps" },
    { "<leader>sM", function() require('telescope.builtin').man_pages() end, desc = "Man Pages" },
    { "<leader>sm", function() require('telescope.builtin').marks() end, desc = "Jump to Mark" },
    { "<leader>so", function() require('telescope.builtin').vim_options() end, desc = "Telescope options" },
    { "<leader>sR", function() require('telescope.builtin').resume() end, desc = "Telescope resume" },
    { "<leader>uC", function() require('telescope.builtin').colorscheme() end, desc = "Telescope colorscheme with preview" },
    {
      "<leader>ss",
      function()
        require("telescope.builtin").lsp_document_symbols({
          symbols = require("lazyvim.config").get_kind_filter(),
        })
      end,
      desc = "Goto Symbol",
    },
    {
      "<leader>sS",
      function()
        require("telescope.builtin").lsp_dynamic_workspace_symbols({
          symbols = require("lazyvim.config").get_kind_filter(),
        })
      end,
      desc = "Goto Symbol (Workspace)",
    },
  },
  opts = function()
    local actions = require("telescope.actions")

    local open_with_trouble = function(...)
      return require("trouble.providers.telescope").open_with_trouble(...)
    end
    local open_selected_with_trouble = function(...)
      return require("trouble.providers.telescope").open_selected_with_trouble(...)
    end
    local find_files_no_ignore = function()
      local action_state = require("telescope.actions.state")
      local line = action_state.get_current_line()
      require("lazyvim.util").telescope("find_files", { no_ignore = true, default_text = line })()
    end
    local find_files_with_hidden = function()
      local action_state = require("telescope.actions.state")
      local line = action_state.get_current_line()
      require("lazyvim.util").telescope("find_files", { hidden = true, default_text = line })()
    end

    return {
      defaults = {
        prompt_prefix = " ",
        selection_caret = " ",
        -- open files in the first window that is an actual file.
        -- use the current window if no other window is available.
        get_selection_window = function()
          local wins = vim.api.nvim_list_wins()
          table.insert(wins, 1, vim.api.nvim_get_current_win())
          for _, win in ipairs(wins) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].buftype == "" then
              return win
            end
          end
          return 0
        end,
        mappings = {
          i = {
            ["<c-t>"] = open_with_trouble,
            ["<a-t>"] = open_selected_with_trouble,
            ["<a-i>"] = find_files_no_ignore,
            ["<a-h>"] = find_files_with_hidden,
            ["<C-f>"] = actions.preview_scrolling_down,
            ["<C-b>"] = actions.preview_scrolling_up,
            ["<C-Down>"] = actions.cycle_history_next,
            ["<C-Up>"] = actions.cycle_history_prev,
          },
          n = {
            ["q"] = actions.close,
          },
        },
      },
    }
  end,
}
