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
        -- Same for the generated base16 palette's base00/base01 (Normal and
        -- the LineNr/CursorLine/TabLine/StatusLine tier): in dark themes they
        -- vanish into the transparent bg, in light themes they are near-white
        -- and paint opaque stripes over the glass.
        local strip = { [0] = true }
        local ok, gen = pcall(dofile, vim.fn.expand("~/.config/nvim/colors.lua"))
        if ok and type(gen) == "table" and gen.palette then
          for _, k in ipairs({ "base00", "base01" }) do
            strip[tonumber(gen.palette[k]:sub(2), 16)] = true
          end
        end
        for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
          if strip[hl.bg] then
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
