return {
  {
    "f-person/auto-dark-mode.nvim",
    init = function()
      local auto_dark_mode = require("auto-dark-mode")
      auto_dark_mode.setup({
        update_interval = 1000,
        set_dark_mode = function()
          vim.api.nvim_set_option("background", "dark")
          -- vim.cmd("colorscheme tokyonight-storm")
          -- vim.cmd("colorscheme onedark")
          vim.cmd("colorscheme elflord")
          -- vim.cmd("colorscheme evening")
        end,
        set_light_mode = function()
          vim.api.nvim_set_option("background", "light")
          -- vim.cmd("colorscheme NeoSolarized")
          vim.cmd("colorscheme gruvbox")
          -- vim.cmd("colorscheme peachpuff")
        end,
      })
      auto_dark_mode.init()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
