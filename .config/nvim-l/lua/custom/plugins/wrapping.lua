return {
  {
    "andrewferrier/wrapping.nvim",
    config = function()
      require("wrapping").setup()
      vim.cmd("set wrap")
    end,
  },
}
