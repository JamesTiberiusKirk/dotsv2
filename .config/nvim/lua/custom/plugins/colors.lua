return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      -- Apply the current desktop mode immediately at startup.
      vim.cmd("ThemeSync")

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
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("CustomSpellUnderline", { clear = true }),
        callback = set_spell_underline,
      })
      set_spell_underline()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
