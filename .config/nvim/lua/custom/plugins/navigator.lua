return {
    'numToStr/Navigator.nvim',
    config = function()
        require('Navigator').setup()
    end,
    lazy = false,
    keys = {
      {"<C-h>","<CMD>NavigatorLeft<CR>", desc = "Navidate left"},
      {"<C-j>","<CMD>NavigatorDown<CR>", desc = "Navidate down"},
      {"<C-k>","<CMD>NavigatorUp<CR>", desc = "Navidate up"},
      {"<C-l>","<CMD>NavigatorRight<CR>", desc = "Navidate right"},
    },
}
