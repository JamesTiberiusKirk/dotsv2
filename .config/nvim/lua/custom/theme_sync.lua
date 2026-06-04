local M = {}

local function apply(mode)
  if mode == "dark" then
    vim.api.nvim_set_option_value("background", "dark", {})
    vim.cmd("colorscheme elflord")
  elseif mode == "light" then
    vim.api.nvim_set_option_value("background", "light", {})
    vim.cmd("colorscheme gruvbox")
  else
    vim.notify("Unknown theme mode: " .. tostring(mode), vim.log.levels.WARN)
  end
end

function M.apply(mode)
  apply(mode)
end

vim.api.nvim_create_user_command("ThemeSync", function(opts)
  local mode = opts.args

  if mode == "" then
    local mode_file = vim.fn.expand("~/.theme-mode")
    if vim.fn.filereadable(mode_file) == 1 then
      mode = vim.trim(table.concat(vim.fn.readfile(mode_file), "\n"))
    end
  end

  if mode == "" then
    mode = "dark" -- default when no file exists
  end

  apply(mode)
end, {
  nargs = "?",
  complete = function()
    return { "dark", "light" }
  end,
})

return M
