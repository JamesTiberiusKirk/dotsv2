return {
  {
    "kassio/neoterm",
    -- keys = {
    --   { "<leader>L", "<cmd>Tclear!<cr>", desc = "Clear terminal" },
    -- },
  },
  {
    "vim-test/vim-test",
    init = function()
      vim.cmd([[
            let test#strategy = "neoterm"
        ]])
    end,
    keys = {
      { "<leader>tl", "<cmd>Tclear <cr>", desc = "Clear terminal" },
      { "<leader>t", "<cmd>TestNearest <cr>", desc = "Test nearest function" },
      -- {
      --   "<leader>t",
      --   function()
      --     vim.cmd("vsplit")
      --     vim.cmd("TestNearest")
      --   end,
      --   desc = "Test nearest function",
      -- },
      { "<leader>T", "<cmd>TestFile -v <cr>", desc = "Test entire file" },
      -- {
      --   "<leader>T",
      --   function()
      --     vim.cmd("vsplit")
      --     vim.cmd("TestFile")
      --   end,
      --   desc = "Test entire file",
      -- },
    },
  },
}
