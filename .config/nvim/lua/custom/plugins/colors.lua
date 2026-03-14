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

      -- Make spell highlights underline-only (no red/fg), and persist across colorscheme changes
      local function set_spell_underline()
        local groups = { "SpellBad", "SpellCap", "SpellLocal", "SpellRare" }
        for _, g in ipairs(groups) do
          vim.api.nvim_set_hl(0, g, {
            underline = true,
            undercurl = false,
            fg = "NONE",
            sp = "NONE",
          })
        end
      end
      local aug = vim.api.nvim_create_augroup("CustomSpellUnderline", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = aug,
        callback = set_spell_underline,
      })

      auto_dark_mode.init()

      -- Apply once at startup as well
      set_spell_underline()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
