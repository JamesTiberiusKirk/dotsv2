return {
  -- mini.nvim suite: align lives here
  {
    'echasnovski/mini.nvim',
    version = '*',
    config = function()
      require('mini.align').setup()
    end,
  },
}
