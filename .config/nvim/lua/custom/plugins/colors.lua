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
        -- Most themes reuse the same hex for base01 and base02 (Visual's bg),
        -- so stripping by color would make visual-mode selection invisible.
        for name, hl in pairs(vim.api.nvim_get_hl(0, {})) do
          if strip[hl.bg] and name ~= "Visual" then
            hl.bg = nil
            hl.ctermbg = nil
            vim.api.nvim_set_hl(0, name, hl)
          end
        end
      end

      -- Push Visual's bg away from the canvas so the selection stands out:
      -- brighten in dark mode, darken in light.
      local function boost_visual()
        local hl = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
        if not hl.bg then return end
        local k = vim.o.background == "dark" and 1.4 or 0.85
        local r = math.min(255, math.floor(math.fmod(math.floor(hl.bg / 65536), 256) * k))
        local g = math.min(255, math.floor(math.fmod(math.floor(hl.bg / 256), 256) * k))
        local b = math.min(255, math.floor(math.fmod(hl.bg, 256) * k))
        hl.bg = r * 65536 + g * 256 + b
        vim.api.nvim_set_hl(0, "Visual", hl)
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("CustomSpellUnderline", { clear = true }),
        callback = function()
          set_spell_underline()
          set_diff_transparent_fg()
          set_transparent_bg()
          boost_visual()
        end,
      })
      set_spell_underline()
      set_diff_transparent_fg()
      set_transparent_bg()
      boost_visual()
    end,
  },
  { "ellisonleao/gruvbox.nvim" },
  { "pineapplegiant/spaceduck" },
  { "folke/tokyonight.nvim" },
  { "overcache/NeoSolarized" },
}
