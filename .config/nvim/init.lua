vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

require('custom.config.options')
require('custom.config.keymaps')
require('custom.config.commands')
require('custom.config.flutter').setup()

-- [[ Install `lazy.nvim` plugin manager ]]
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- [[ Configure plugins ]]
-- NOTE: Here is where you install your plugins.
--  You can configure plugins using the `config` key.
--
--  You can also configure plugins after the setup call,
--    as they will be available in your neovim runtime.
require('lazy').setup({
  -- NOTE: First, some plugins that don't require any configuration

  -- Git related plugins
  'tpope/vim-fugitive',
  'tpope/vim-rhubarb',

  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- NOTE: This is where your plugins related to LSP can be installed.
  --  The configuration is done below. Search for lspconfig to find it below.
  {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs to stdpath for neovim
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
      "davidosomething/format-ts-errors.nvim",

      -- Useful status updates for LSP
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = {} },

      -- Additional lua configuration, makes nvim stuff amazing!
      'folke/neodev.nvim',
    },
    config = function()
      -- NOTE: Previously we configured gopls and ts here directly via lspconfig.
      -- Keeping for reference, but commented out to avoid duplicate clients.
      -- local lspconfig = require("lspconfig")
      -- lspconfig.gopls.setup{ settings = { gopls = { buildFlags = {"-tags=integration"}, env = { GOFLAGS = "-tags=integration" }, }, }, }
      -- lspconfig.ts_ls.setup({ handlers = { ["textDocument/publishDiagnostics"] = function(_, result, ctx, config) ... end } })
    end,
  },
  {
    -- Autocompletion
    'hrsh7th/nvim-cmp',
    dependencies = {
      -- {
      --     "zbirenbaum/copilot-cmp",
      --     config = function()
      --         require("copilot_cmp").setup()
      --     end,
      -- },
      -- Snippet Engine & its associated nvim-cmp source
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',

      -- Adds LSP completion capabilities
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-cmdline',
      "hrsh7th/cmp-buffer",

      -- Adds a number of user-friendly snippets
      'rafamadriz/friendly-snippets',
    },
  },

  -- Useful plugin to show you pending keybinds.
  { 'folke/which-key.nvim',  opts = {} },
  {
    -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      -- See `:help gitsigns.txt`
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns

        local function map(mode, l, r, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, l, r, opts)
        end

        -- Navigation
        map({ 'n', 'v' }, ']c', function()
          if vim.wo.diff then
            return ']c'
          end
          vim.schedule(function()
            gs.next_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, desc = 'Jump to next hunk' })

        map({ 'n', 'v' }, '[c', function()
          if vim.wo.diff then
            return '[c'
          end
          vim.schedule(function()
            gs.prev_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, desc = 'Jump to previous hunk' })

        -- Actions
        -- visual mode
        map('v', '<leader>hs', function()
          gs.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'stage git hunk' })
        map('v', '<leader>hr', function()
          gs.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
        end, { desc = 'reset git hunk' })
        -- normal mode
        map('n', '<leader>hs', gs.stage_hunk, { desc = 'git stage hunk' })
        map('n', '<leader>hr', gs.reset_hunk, { desc = 'git reset hunk' })
        map('n', '<leader>hS', gs.stage_buffer, { desc = 'git Stage buffer' })
        map('n', '<leader>hu', gs.undo_stage_hunk, { desc = 'undo stage hunk' })
        map('n', '<leader>hR', gs.reset_buffer, { desc = 'git Reset buffer' })
        map('n', '<leader>hp', gs.preview_hunk, { desc = 'preview git hunk' })
        map('n', '<leader>hb', function()
          gs.blame_line { full = false }
        end, { desc = 'git blame line' })
        map('n', '<leader>hd', gs.diffthis, { desc = 'git diff against index' })
        map('n', '<leader>hD', function()
          gs.diffthis '~'
        end, { desc = 'git diff against last commit' })

        -- Toggles
        map('n', '<leader>tb', gs.toggle_current_line_blame, { desc = 'toggle git blame line' })
        map('n', '<leader>td', gs.toggle_deleted, { desc = 'toggle git show deleted' })

        -- Text object
        map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', { desc = 'select git hunk' })
      end,
    },
  },

  {
    -- Theme inspired by Atom
    'navarasu/onedark.nvim',
    priority = 1000,
    config = function()
      -- vim.cmd.colorscheme 'onedark'
    end,
  },

  {
    -- Set lualine as statusline
    'nvim-lualine/lualine.nvim',
    -- See `:help lualine.txt`
    opts = {
      options = {
        icons_enabled = false,
        theme = 'auto',
        component_separators = '|',
        section_separators = '',
      },
      sections = {
        lualine_a = {'mode'},
        lualine_b = {'branch', 'diff', 'diagnostics'},
        lualine_c = {
          {
            'filename',
            file_status = true,      -- Displays file status (readonly status, modified status)
            newfile_status = false,  -- Display new file status (new file means no write after created)
            path = 1,                -- 0: Just the filename
            -- 1: Relative path
            -- 2: Absolute path
            -- 3: Absolute path, with tilde as the home directory
            -- 4: Filename and parent dir, with tilde as the home directory

            shorting_target = 40,    -- Shortens path to leave 40 spaces in the window
            -- for other components. (terrible name, any suggestions?)
            symbols = {
              modified = '[+]',      -- Text to show when the file is modified.
              readonly = '[-]',      -- Text to show when the file is non-modifiable or readonly.
              unnamed = '[No Name]', -- Text to show for unnamed buffers.
              newfile = '[New]',     -- Text to show for newly created file before first write
            }
          }
        },
        lualine_x = {'encoding', 'fileformat', 'filetype'},
        lualine_y = {'progress'},
        lualine_z = {'location'}
      },
    },
  },

  {
    -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    -- Enable `lukas-reineke/indent-blankline.nvim`
    -- See `:help ibl`
    main = 'ibl',
    opts = {
    },
    init = function()
      local highlight = {
        "RainbowRed",
        "RainbowYellow",
        "RainbowBlue",
        "RainbowOrange",
        "RainbowGreen",
        "RainbowViolet",
        "RainbowCyan",
      }
      local hooks = require "ibl.hooks"
      -- create the highlight groups in the highlight setup hook, so they are reset
      -- every time the colorscheme changes
      hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
        vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
        vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
        vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
        vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
        vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
        vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
        vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
      end)

      vim.g.rainbow_delimiters = { highlight = highlight }
      require("ibl").setup {
        scope = {
          highlight = highlight
        },
        exclude = {
          -- filetypes = { "templ" }
        }
      }

      hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
    end,
  },

  -- "gc" to comment visual regions/lines
  {
    'numToStr/Comment.nvim',
    opts = {},
    init = function ()
      local ft = require('Comment.ft')
      ft({'templ'}, ft.get('c'))
    end
  },

  {
    -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
      'vrischmann/tree-sitter-templ',
    },
    build = ':TSUpdate',
  },

  {
    "f-person/git-blame.nvim",
    config = function ()
      vim.g.gitblame_date_format = '%c'
      vim.g.gitblame_message_template = '\t\t<summary> • <date> • <author>'
    end,
  },

  -- NOTE: Next Step on Your Neovim Journey: Add/Configure additional "plugins" for kickstart
  --       These are some example plugins that I've included in the kickstart repository.
  --       Uncomment any of the lines below to enable them.
  -- require 'kickstart.plugins.autoformat',
  -- require 'kickstart.plugins.debug',

  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    You can use this folder to prevent any conflicts with this init.lua if you're interested in keeping
  --    up-to-date with whatever is in the kickstart repo.
  --    Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  --
  --    For additional information see: https://github.com/folke/lazy.nvim#-structuring-your-plugins
  { import = 'custom.plugins' },
}, {})



-- [[ Highlight on yank ]]
-- See `:help vim.highlight.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.highlight.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})

-- [[ Configure Telescope ]]
-- See `:help telescope` and `:help telescope.setup()`
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ['<C-u>'] = false,
        ['<C-d>'] = false,
      },
    },
  },
}

-- Enable telescope fzf native, if installed
pcall(require('telescope').load_extension, 'fzf')

-- Apply global Telescope theme wrapper and toggle
require('custom.config.telescope')

-- Telescope live_grep in git root
-- Function to find the git root directory based on the current buffer's path
local function find_git_root()
  -- Use the current buffer's path as the starting point for the git search
  local current_file = vim.api.nvim_buf_get_name(0)
  local current_dir
  local cwd = vim.fn.getcwd()
  -- If the buffer is not associated with a file, return nil
  if current_file == '' then
    current_dir = cwd
  else
    -- Extract the directory from the current file's path
    current_dir = vim.fn.fnamemodify(current_file, ':h')
  end

  -- Find the Git root directory from the current file's path
  local git_root = vim.fn.systemlist('git -C ' .. vim.fn.escape(current_dir, ' ') .. ' rev-parse --show-toplevel')[1]
  if vim.v.shell_error ~= 0 then
    print 'Not a git repository. Searching on current working directory'
    return cwd
  end
  return git_root
end

-- Custom live_grep function to search in git root
local function live_grep_git_root()
  local git_root = find_git_root()
  if git_root then
    require('telescope.builtin').live_grep {
      search_dirs = { git_root },
    }
  end
end

vim.api.nvim_create_user_command('LiveGrepGitRoot', live_grep_git_root, {})

-- See `:help telescope.builtin`
vim.keymap.set('n', '<leader>?', function()
  require('telescope.builtin').oldfiles()
end, { desc = '[?] Find recently opened files' })
vim.keymap.set('n', '<leader><space>', function()
  require('telescope.builtin').buffers()
end, { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<leader>/', function()
  -- Global theme is applied; just tweak opts if desired
  require('telescope.builtin').current_buffer_fuzzy_find({ winblend = 10, previewer = false })
end, { desc = '[/] Fuzzily search in current buffer' })

-- local function telescope_live_grep_open_files()
--   require('telescope.builtin').live_grep {
--     grep_open_files = true,
--     prompt_title = 'Live Grep in Open Files',
--   }
-- end
-- vim.keymap.set('n', '<leader>s/', telescope_live_grep_open_files, { desc = '[S]earch [/] in Open Files' })
-- vim.keymap.set('n', '<leader>ss', require('telescope.builtin').builtin, { desc = '[S]earch [S]elect Telescope' })
-- vim.keymap.set('n', '<leader>gf', require('telescope.builtin').git_files, { desc = 'Search [G]it [F]iles' })
-- vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
-- vim.keymap.set('n', '<leader>sh', require('telescope.builtin').help_tags, { desc = '[S]earch [H]elp' })
-- vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch current [W]ord' })
-- vim.keymap.set('n', '<leader>sg', require('telescope.builtin').live_grep, { desc = '[S]earch by [G]rep' })
-- vim.keymap.set('n', '<leader>sG', ':LiveGrepGitRoot<cr>', { desc = '[S]earch by [G]rep on Git Root' })
-- vim.keymap.set('n', '<leader>sd', require('telescope.builtin').diagnostics, { desc = '[S]earch [D]iagnostics' })
-- vim.keymap.set('n', '<leader>sr', require('telescope.builtin').resume, { desc = '[S]earch [R]esume' })
--
-- [[ Configure Treesitter ]]
-- See `:help nvim-treesitter`
require('nvim-treesitter').install {
  'c', 'cpp', 'dart', 'go', 'lua', 'python', 'rust', 'tsx',
  'javascript', 'typescript', 'vimdoc', 'vim', 'bash', 'templ',
  'html', 'css', 'java', 'sql',
}

-- Enable treesitter highlighting for all installed parsers
vim.api.nvim_create_autocmd('FileType', {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- Textobjects
require('nvim-treesitter-textobjects').setup {
  select = {
    lookahead = true,
  },
  move = {
    set_jumps = true,
  },
}

-- Textobject select keymaps
local select_keymap = {
  ['aa'] = '@parameter.outer',
  ['ia'] = '@parameter.inner',
  ['af'] = '@function.outer',
  ['if'] = '@function.inner',
  ['ac'] = '@class.outer',
  ['ic'] = '@class.inner',
}
for key, query in pairs(select_keymap) do
  vim.keymap.set({ 'x', 'o' }, key, function()
    require('nvim-treesitter-textobjects.select').select_textobject(query, 'textobjects')
  end)
end

-- Textobject move keymaps
local move = require('nvim-treesitter-textobjects.move')
local move_keymaps = {
  { ']m', move.goto_next_start, '@function.outer' },
  { ']]', move.goto_next_start, '@class.outer' },
  { ']M', move.goto_next_end, '@function.outer' },
  { '][', move.goto_next_end, '@class.outer' },
  { '[m', move.goto_previous_start, '@function.outer' },
  { '[[', move.goto_previous_start, '@class.outer' },
  { '[M', move.goto_previous_end, '@function.outer' },
  { '[]', move.goto_previous_end, '@class.outer' },
}
for _, map in ipairs(move_keymaps) do
  vim.keymap.set({ 'n', 'x', 'o' }, map[1], function() map[2](map[3], 'textobjects') end)
end

-- Textobject swap keymaps
local swap = require('nvim-treesitter-textobjects.swap')
vim.keymap.set('n', '<leader>a', function() swap.swap_next('@parameter.inner') end)
vim.keymap.set('n', '<leader>A', function() swap.swap_previous('@parameter.inner') end)

-- [[ Configure LSP ]]

-- Go-to-definition that redirects _templ.go targets to the original .templ source
local function goto_definition_or_templ()
  local word = vim.fn.expand('<cword>')
  local client = vim.lsp.get_clients({ bufnr = 0 })[1]
  local encoding = client and client.offset_encoding or 'utf-8'
  local params = vim.lsp.util.make_position_params(0, encoding)

  vim.lsp.buf_request(0, 'textDocument/definition', params, function(err, result, ctx)
    if err or not result or (vim.islist(result) and #result == 0) then
      if not err then
        vim.notify('No definition found', vim.log.levels.INFO)
      end
      return
    end

    local results = vim.islist(result) and result or { result }
    local target = results[1]
    local uri = target.uri or target.targetUri

    if uri then
      local path = vim.uri_to_fname(uri)
      if path:match('_templ%.go$') then
        local templ_path = path:gsub('_templ%.go$', '.templ')
        if vim.fn.filereadable(templ_path) == 1 then
          vim.schedule(function()
            vim.cmd("normal! m'")
            vim.cmd('edit ' .. vim.fn.fnameescape(templ_path))
            for _, pat in ipairs({
              [[\<templ\s\+]] .. word .. [[\>]],
              [[\<func\s\+]] .. word .. [[\>]],
              [[\<css\s\+]] .. word .. [[\>]],
              [[\<script\s\+]] .. word .. [[\>]],
            }) do
              if vim.fn.search(pat, 'w') > 0 then
                return
              end
            end
          end)
          return
        end
      end
    end

    -- Default: jump normally
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    local encoding = client and client.offset_encoding or 'utf-8'
    vim.lsp.util.jump_to_location(target, encoding)
  end)
end

--  This function gets run when an LSP connects to a particular buffer.
local on_attach = function(_, bufnr)

  -- NOTE: Remember that lua is a real programming language, and as such it is possible
  -- to define small helper and utility functions so you don't have to repeat yourself
  -- many times.
  --
  -- In this case, we create a function that lets us more easily define mappings specific
  -- for LSP related items. It sets the mode, buffer and description for us each time.
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  -- nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
  -- nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  -- nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  -- nmap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
  -- nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  -- nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
  --
  nmap('gd', goto_definition_or_templ, '[G]oto [D]efinition')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('I', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- document existing key chains
local ws = require('which-key')
ws.add{
    { "<leader>c", group = "[C]ode" },
    { "<leader>c_", hidden = true },
    { "<leader>F", group = "[F]lutter" },
    { "<leader>F_", hidden = true },
    { "<leader>d", group = "[D]ocument" },
    { "<leader>d_", hidden = true },
    { "<leader>g", group = "[G]it" },
    { "<leader>g_", hidden = true },
    { "<leader>h", group = "Git [H]unk" },
    { "<leader>h_", hidden = true },
    { "<leader>r", group = "[R]ename" },
    { "<leader>r_", hidden = true },
    { "<leader>s", group = "[S]earch" },
    { "<leader>s_", hidden = true },
    { "<leader>t", group = "[T]oggle" },
    { "<leader>t_", hidden = true },
    { "<leader>u", group = "[U]I" },
    { "<leader>w", group = "[W]orkspace" },
    { "<leader>w_", hidden = true },

    { "<leader>", group = "VISUAL <leader>" },
    { "<leader>h", group = "Git [H]unk" },
  }
-- register which-key VISUAL mode
-- required for visual <leader>hs (hunk stage) to work
-- ws.add({
--     ["<leader>"] = {
--       name = "VISUAL <leader>"
--     },
--     ["<leader>h"] = { "Git [H]unk" },
-- }, { mode = 'v' })

require('mason').setup()
require('mason-lspconfig').setup()

vim.filetype.add({ extension = { templ = "templ" } })

local servers = {
  -- clangd = {},
  gopls = {
    gopls = {
      buildFlags = { "-tags=integration" },
      env = { GOFLAGS = "-tags=integration" },
      usePlaceholders = true,
    },
  },
  ts_ls = {},
  jdtls = {},
  dartls = {},
  -- pyright = {},
  -- rust_analyzer = {},
  -- html = { filetypes = { 'html', 'twig', 'hbs', 'templ' }},
  -- htmx = { filetypes = {'html', 'templ' }},
  -- templ = { filetypes = { 'templ' }},
  -- tailwindcss = {
  --   filetypes = { "templ", "astro", "javascript", "typescript", "react", "js", "ts", "tsx", "jsx" },
  --   tailwindcss = {
  --     init_options = {
  --       userLanguages = {
  --         templ = "html"
  --       }
  --     },
  --   },
  -- },
  lua_ls = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
      -- NOTE: toggle below to ignore Lua_LS's noisy `missing-fields` warnings
      -- diagnostics = { disable = { 'missing-fields' } },
    },
  },
}



-- Setup neovim lua configuration
require('neodev').setup()

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- Ensure the servers above are installed
require('mason-lspconfig').setup {
  ensure_installed = vim.tbl_filter(function(server_name)
    return server_name ~= 'dartls'
  end, vim.tbl_keys(servers)),
}

-- Global LSP defaults
vim.lsp.config('*', {
  capabilities = capabilities,
  on_attach = on_attach,
  flags = { debounce_text_changes = 150 },
})

-- Configure each server from the servers table
for server_name, server_settings in pairs(servers) do
  local cfg = {
    settings = server_settings,
    filetypes = server_settings.filetypes,
  }
  if server_name == 'ts_ls' then
    cfg.handlers = {
      ["textDocument/publishDiagnostics"] = function(_, result, ctx, config)
        if result.diagnostics == nil then return end
        local idx = 1
        while idx <= #result.diagnostics do
          local entry = result.diagnostics[idx]
          local formatter = require('format-ts-errors')[entry.code]
          entry.message = formatter and formatter(entry.message) or entry.message
          if entry.code == 80001 then
            table.remove(result.diagnostics, idx)
          else
            idx = idx + 1
          end
        end
        vim.lsp.diagnostic.on_publish_diagnostics(_, result, ctx, config)
      end,
    }
  end
  vim.lsp.config(server_name, cfg)
end

-- Dart LSP with Flutter-specific config
local flutter = require('custom.config.flutter')
vim.lsp.config('dartls', {
  settings = vim.tbl_deep_extend('force', servers.dartls or {}, {
    dart = {
      completeFunctionCalls = true,
      showTodos = true,
    },
  }),
  init_options = {
    closingLabels = true,
    flutterOutline = true,
    onlyAnalyzeProjectsWithOpenFiles = false,
    outline = true,
    suggestFromUnimportedLibraries = true,
  },
  cmd = flutter.resolve_dartls_cmd(vim.fn.getcwd()),
  cmd_env = flutter.dartls_env(vim.fn.getcwd()),
  on_new_config = function(new_config, new_root_dir)
    local cmd = flutter.resolve_dartls_cmd(new_root_dir)
    if cmd then
      new_config.cmd = cmd
    end
    new_config.cmd_env = flutter.dartls_env(new_root_dir, new_config.cmd_env)
  end,
})

-- Additional servers
vim.lsp.config('tailwindcss', {
  filetypes = { "templ", "astro", "javascript", "typescript", "react" },
  init_options = { userLanguages = { templ = "html" } },
})

vim.lsp.config('templ', {})

vim.lsp.config('html', {
  filetypes = { "html", "templ" },
})

vim.lsp.config('htmx', {
  filetypes = { "html", "templ" },
})

-- Enable all configured servers
vim.lsp.enable(vim.tbl_keys(servers))
vim.lsp.enable({ 'tailwindcss', 'templ', 'html', 'htmx' })

-- Templ stuff
local templ_format = function()
    if vim.bo.filetype == "templ" then
        local bufnr = vim.api.nvim_get_current_buf()
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local cmd = "templ fmt " .. vim.fn.shellescape(filename)

        vim.fn.jobstart(cmd, {
            on_exit = function()
                -- Reload the buffer only if it's still the current buffer
                if vim.api.nvim_get_current_buf() == bufnr then
                    vim.cmd('e!')
                end
            end,
        })
    else
        vim.lsp.buf.format()
    end
end

vim.api.nvim_create_autocmd({ "BufWritePre" }, { pattern = { "*.templ" }, callback = templ_format })






-- [[ Configure nvim-cmp ]]
-- See `:help cmp`
local cmp = require 'cmp'
local luasnip = require 'luasnip'
require('luasnip.loaders.from_vscode').lazy_load()
luasnip.config.setup {}

-- Use buffer source for `/` (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline('/', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = {
    { name = 'buffer' },
  },
})

-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' },
  }, {
    { name = 'cmdline' },
  }),
})

-- Helper: detect non-normal buffers (prompts, sidebars, popups)
local function is_prompt_like()
  local bt = vim.bo.buftype
  local ft = vim.bo.filetype
  if bt ~= '' and bt ~= 'acwrite' then
    return true
  end
  return ft == 'TelescopePrompt' or ft == 'neo-tree' or ft == 'neo-tree-popup'
end

cmp.setup {
  enabled = function()
    return vim.g.cmptoggle and not is_prompt_like()
  end,
  window = {
    documentation = cmp.config.window.bordered(),
  },
  snippet = {
    expand = function(args)
      luasnip.lsp_expand(args.body)
    end,
  },
  completion = {
    completeopt = 'menu,menuone,noinsert',
  },
  mapping = cmp.mapping.preset.insert {
    ['<C-n>'] = cmp.mapping.select_next_item(),
    ['<C-p>'] = cmp.mapping.select_prev_item(),
    ['<C-d>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete {},
    ['<CR>'] = cmp.mapping.confirm {
      behavior = cmp.ConfirmBehavior.Replace,
      select = true,
    },
    ['<Tab>'] = cmp.mapping(function(fallback)
      if is_prompt_like() then
        return fallback()
      end
      if cmp.visible() then
        cmp.select_next_item()
      elseif luasnip.expand_or_locally_jumpable() then
        luasnip.expand_or_jump()
      else
        fallback()
      end
    end, { 'i', 's' }),
    ['<S-Tab>'] = cmp.mapping(function(fallback)
      if is_prompt_like() then
        return fallback()
      end
      if cmp.visible() then
        cmp.select_prev_item()
      elseif luasnip.locally_jumpable(-1) then
        luasnip.jump(-1)
      else
        fallback()
      end
    end, { 'i', 's' }),
  },
  sources = {
    { name = 'nvim_lsp' },
    -- { name = 'luasnip' },
    -- { name = 'buffer' },
    -- { name = 'path' },
  },
}

vim.g.cmptoggle = true

vim.keymap.set("n", "<leader>ua", "<cmd>lua vim.g.cmptoggle = not vim.g.cmptoggle<CR>", { desc = "toggle nvim-cmp" })


-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
