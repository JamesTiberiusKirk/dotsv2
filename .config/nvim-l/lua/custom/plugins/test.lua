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
            let test#go#runner = 'gotest'
            let test#go#gotest#options = '-v -race'
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
      { "<leader>T", "<cmd>TestFile<cr>", desc = "Test entire file" },
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
