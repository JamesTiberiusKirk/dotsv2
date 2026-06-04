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

      local function set_diff_transparent_fg()
        for _, g in ipairs({ "DiffAdd", "DiffDelete", "DiffChange", "DiffText" }) do
          local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
          hl.fg = nil
          vim.api.nvim_set_hl(0, g, hl)
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("CustomSpellUnderline", { clear = true }),
        callback = function()
          set_spell_underline()
          set_diff_transparent_fg()
        end,
      })
      set_spell_underline()
      set_diff_transparent_fg()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
