vim.opt.clipboard = "unnamedplus"

-- Force use of xclip for X11 instead of wl-copy
if os.getenv("WAYLAND_DISPLAY") == nil and os.getenv("DISPLAY") ~= nil then
  vim.g.clipboard = {
    name = 'xclip',
    copy = {
      ['+'] = 'xclip -selection clipboard',
      ['*'] = 'xclip -selection primary',
    },
    paste = {
      ['+'] = 'xclip -selection clipboard -o',
      ['*'] = 'xclip -selection primary -o',
    },
    cache_enabled = 1,
  }
end

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "number"

