return {
  'kawre/leetcode.nvim',
  build = function()
    vim.cmd 'TSUpdate html'
  end,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  opts = {
    lang = 'golang',
    storage = {
      home = vim.fn.expand '~/Projects/leetcode',
    },
    theme = {
      ['normal'] = { fg = '#d4d4d4' },
      ['code'] = { fg = '#ce9178', bg = 'NONE' },
    },
  },
}
