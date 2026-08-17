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

      -- Clear the main background groups so the terminal's transparency (and
      -- the compositor's glass effect) shows through inside the editor.
      -- ctermfg=NONE keeps syntax groups that default to a dark cterm color
      -- (e.g. LineNr) from going invisible on dark terminal backgrounds.
      local function set_transparent_bg()
        local groups = { "Normal", "NormalNC", "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn", "MsgArea" }
        for _, g in ipairs(groups) do
          vim.api.nvim_set_hl(0, g, { bg = "NONE", ctermbg = "NONE", ctermfg = "NONE" })
        end
        -- The regenerated builtin schemes (e.g. elflord) bake guibg=#000000 into
        -- every group; strip those so transparency shows through everywhere.
        for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
          if hl.bg == 0 then
            hl.bg = nil
            hl.ctermbg = nil
            vim.api.nvim_set_hl(0, name, hl)
          end
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("CustomSpellUnderline", { clear = true }),
        callback = function()
          set_spell_underline()
          set_diff_transparent_fg()
          set_transparent_bg()
        end,
      })
      set_spell_underline()
      set_diff_transparent_fg()
      set_transparent_bg()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
