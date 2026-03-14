local M = {}

-- Default theme: 'dropdown' or 'stack' (maps to 'ivy')
vim.g.telescope_theme = vim.g.telescope_theme or 'dropdown'

local function themed_opts(opts)
  opts = opts or {}
  local themes = require('telescope.themes')
  local theme = (vim.g.telescope_theme == 'stack') and 'ivy' or 'dropdown'
  if theme == 'ivy' then
    return themes.get_ivy(opts)
  else
    return themes.get_dropdown(opts)
  end
end

-- Monkey patch builtins to always apply theme unless opts.__skip_global_theme
local function patch_builtins()
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then return end
  for k, fn in pairs(builtin) do
    if type(fn) == 'function' then
      builtin[k] = function(opts)
        if not (opts and opts.__skip_global_theme) then
          opts = themed_opts(opts)
        end
        return fn(opts)
      end
    end
  end
end

-- Patch extensions to apply theme as well
local function patch_extensions()
  local ok, telescope = pcall(require, 'telescope')
  if not ok then return end
  local exts = telescope.extensions or {}
  for _, ext in pairs(exts) do
    if type(ext) == 'table' then
      for k, fn in pairs(ext) do
        if type(fn) == 'function' then
          ext[k] = function(opts)
            if not (opts and opts.__skip_global_theme) then
              opts = themed_opts(opts)
            end
            return fn(opts)
          end
        end
      end
    end
  end
end

function M.set_theme(theme)
  if theme == 'dropdown' or theme == 'stack' then
    vim.g.telescope_theme = theme
  else
    vim.notify('Unknown Telescope theme: ' .. tostring(theme), vim.log.levels.WARN)
    return
  end
  patch_builtins()
  patch_extensions()
  vim.notify('Telescope theme set to: ' .. theme)
end

function M.toggle_theme()
  if vim.g.telescope_theme == 'dropdown' then
    M.set_theme('stack')
  else
    M.set_theme('dropdown')
  end
end

-- Initial patch
patch_builtins()
patch_extensions()

-- User command to toggle themes quickly
vim.api.nvim_create_user_command('TelescopeThemeToggle', function()
  M.toggle_theme()
end, { desc = 'Toggle Telescope theme (dropdown/stack)' })

return M
