return {
  -- mini.nvim suite: align + animate live here
  {
    'echasnovski/mini.nvim',
    version = '*',
    config = function()
      require('mini.align').setup()

      local animate = require('mini.animate')
      animate.setup {
        cursor = {
          timing = animate.gen_timing.linear { duration = 80, unit = 'total' },
        },
        scroll = {
          timing = animate.gen_timing.linear { duration = 120, unit = 'total' },
        },
        resize = {
          timing = animate.gen_timing.linear { duration = 80, unit = 'total' },
        },
        -- these fight with telescope/neo-tree floats
        open = { enable = false },
        close = { enable = false },
      }
    end,
  },
}
