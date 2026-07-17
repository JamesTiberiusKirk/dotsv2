return {
    'numToStr/Navigator.nvim',
    config = function()
        -- If this pane is a gtmux pane, hand off at a vim split edge to gtmux
        -- rather than vi-only nav. Prefer $GTMUX even when $TMUX is also set
        -- (gtmux nested in tmux): the pane belongs to the inner gtmux.
        -- $GTMUX = "socket,pid,session".
        local mux = 'auto'
        local gtmux = os.getenv('GTMUX')
        if gtmux then
            local p = vim.split(gtmux, ',')
            local sock, session = p[1], p[3]
            local dir = { p = 'l', h = 'L', k = 'U', l = 'R', j = 'D' }
            mux = {
                navigate = function(_, d)
                    vim.fn.system(('GTMUX_SOCK=%s gtmux run %s select-pane -%s')
                        :format(sock, session, dir[d]))
                end,
                zoomed = function() return false end,
            }
        end
        require('Navigator').setup({ mux = mux })
    end,
    lazy = false,
    keys = {
      {"<C-h>","<CMD>NavigatorLeft<CR>", desc = "Navidate left"},
      {"<C-j>","<CMD>NavigatorDown<CR>", desc = "Navidate down"},
      {"<C-k>","<CMD>NavigatorUp<CR>", desc = "Navidate up"},
      {"<C-l>","<CMD>NavigatorRight<CR>", desc = "Navidate right"},
    },
}
