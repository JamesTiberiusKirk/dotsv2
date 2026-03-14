local M = {}

local active = false
local amount_default = 3
local augroup_name = 'ResizeMode'

-- Track installed buffer-local maps so we can remove them on stop
local installed = {}

local function echo(msg)
  vim.api.nvim_echo({ { msg, 'ModeMsg' } }, false, {})
end

local function do_resize(dir, amt)
  amt = tonumber(amt) or amount_default
  if dir == 'left' then
    vim.cmd('vertical resize -' .. amt)
  elseif dir == 'right' then
    vim.cmd('vertical resize +' .. amt)
  elseif dir == 'up' then
    vim.cmd('resize +' .. amt)
  elseif dir == 'down' then
    vim.cmd('resize -' .. amt)
  end
end

local function map_buf(buf, lhs, rhs, desc)
  vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, noremap = true, nowait = true, desc = desc })
  installed[buf] = installed[buf] or {}
  installed[buf][lhs] = true
end

local function apply_maps(buf, amt)
  -- Core i3-style hjkl
  map_buf(buf, 'h', function() do_resize('left', amt) end, 'Resize left')
  map_buf(buf, 'l', function() do_resize('right', amt) end, 'Resize right')
  map_buf(buf, 'k', function() do_resize('up', amt) end, 'Resize up')
  map_buf(buf, 'j', function() do_resize('down', amt) end, 'Resize down')

  -- Faster with uppercase (5x)
  map_buf(buf, 'H', function() do_resize('left', amt * 5) end, 'Resize left x5')
  map_buf(buf, 'L', function() do_resize('right', amt * 5) end, 'Resize right x5')
  map_buf(buf, 'K', function() do_resize('up', amt * 5) end, 'Resize up x5')
  map_buf(buf, 'J', function() do_resize('down', amt * 5) end, 'Resize down x5')

  -- Arrow keys as well
  map_buf(buf, '<Left>', function() do_resize('left', amt) end, 'Resize left')
  map_buf(buf, '<Right>', function() do_resize('right', amt) end, 'Resize right')
  map_buf(buf, '<Up>', function() do_resize('up', amt) end, 'Resize up')
  map_buf(buf, '<Down>', function() do_resize('down', amt) end, 'Resize down')

  -- Exit keys
  map_buf(buf, '<Esc>', function() M.stop() end, 'Exit resize mode')
  map_buf(buf, 'q', function() M.stop() end, 'Exit resize mode')
end

function M.stop()
  if not active then return end
  -- Remove all buffer-local mappings we added
  for buf, keys in pairs(installed) do
    for lhs, _ in pairs(keys) do
      pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
    end
  end
  installed = {}

  -- Clear autocmds
  pcall(vim.api.nvim_del_augroup_by_name, augroup_name)

  active = false
  echo('Resize mode: off')
end

function M.start(opts)
  if active then return end
  opts = opts or {}
  local amt = tonumber(opts.amount) or amount_default

  -- Apply to current buffer
  apply_maps(0, amt)

  -- Apply when switching windows/buffers while in mode
  local grp = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  vim.api.nvim_create_autocmd({ 'WinEnter', 'BufEnter' }, {
    group = grp,
    callback = function(args)
      apply_maps(args.buf, amt)
    end,
    desc = 'Install resize-mode maps on window/buffer switch',
  })

  active = true
  echo('Resize mode: h/j/k/l, Esc/q to exit')
end

function M.toggle(opts)
  if active then M.stop() else M.start(opts) end
end

return M
