local puppeteer_exec =
  '/home/darthvader/.cache/puppeteer/chrome-headless-shell/linux-143.0.7499.192/chrome-headless-shell-linux64/chrome-headless-shell'

if vim.env.PUPPETEER_EXECUTABLE_PATH == nil or vim.env.PUPPETEER_EXECUTABLE_PATH == '' then
  vim.env.PUPPETEER_EXECUTABLE_PATH = puppeteer_exec
end

local function is_kitty_terminal()
  local term = vim.env.TERM or ''
  return vim.env.KITTY_PID ~= nil or term:find('kitty') ~= nil
end

local function tmux_allows_passthrough()
  if vim.env.TMUX == nil then
    return true
  end

  local ok, result = pcall(vim.fn.system, { 'tmux', 'show', '-Apv', 'allow-passthrough' })
  if not ok then
    return false
  end

  return result:sub(-3) == 'on\n' or result:sub(-4) == 'all\n'
end

local function pick_image_backend()
  if is_kitty_terminal() and tmux_allows_passthrough() then
    return 'kitty'
  end

  if vim.fn.executable('ueberzug') == 1 then
    return 'ueberzug'
  end

  return nil
end

local image_backend = pick_image_backend()

return {
  '3rd/diagram.nvim',
  cond = image_backend ~= nil,
  dependencies = {
    {
      '3rd/image.nvim',
      cond = image_backend ~= nil,
      opts = function()
        return { backend = image_backend }
      end,
    }, -- you'd probably want to configure image.nvim manually instead of doing this
  },
  opts = function()
    local has_mmdc = vim.fn.executable('mmdc') == 1

    local function maybe_disable_mermaid(integration)
      if has_mmdc then
        return integration
      end

      if integration._diagram_original_query ~= nil then
        return integration
      end

      integration._diagram_original_query = integration.query_buffer_diagrams
      integration.query_buffer_diagrams = function(bufnr)
        local diagrams = integration._diagram_original_query(bufnr)
        local filtered = {}
        for _, diagram in ipairs(diagrams) do
          if diagram.renderer_id ~= 'mermaid' then
            table.insert(filtered, diagram)
          end
        end
        return filtered
      end

      return integration
    end

    local integrations = {
      maybe_disable_mermaid(require('diagram.integrations.markdown')),
      maybe_disable_mermaid(require('diagram.integrations.neorg')),
    }

    return {
      integrations = integrations,
      -- events = {
      --   render_buffer = { 'InsertLeave', 'BufWinEnter', 'TextChanged' },
      --   clear_buffer = { 'BufLeave' },
      -- },
      renderer_options = {
        mermaid = {
          background = "#0b0b0b", -- nil | "transparent" | "white" | "#hex"
          theme = "forest", -- nil | "default" | "dark" | "forest" | "neutral"
          scale = 2, -- nil | 1 (default) | 2  | 3 | ...
          width = nil, -- nil | 800 | 400 | ...
          height = nil, -- nil | 600 | 300 | ...
          cli_args = nil, -- nil | { "--no-sandbox" } | { "-p", "/path/to/puppeteer" } | ...
        },
        plantuml = {
          charset = nil,
          cli_args = nil, -- nil | { "-Djava.awt.headless=true" } | ...
        },
        d2 = {
          theme_id = nil,
          dark_theme_id = nil,
          scale = nil,
          layout = nil,
          sketch = nil,
          cli_args = nil, -- nil | { "--pad", "0" } | ...
        },
        gnuplot = {
          size = nil, -- nil | "800,600" | ...
          font = nil, -- nil | "Arial,12" | ...
          theme = nil, -- nil | "light" | "dark" | custom theme string
          cli_args = nil, -- nil | { "-p" } | { "-c", "config.plt" } | ...
        },
      },
    }
  end,
}
