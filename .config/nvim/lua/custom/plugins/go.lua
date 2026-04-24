return {
  {
    "fatih/vim-go",
    lazy = false,
    init = function()
      -- On every new install need to run GoInstallBinaries
      --g:go_build_tags
      vim.cmd("let g:go_build_tags='-tags=integration'")
      vim.cmd("let g:go_gocode_autobuild=0")
      vim.cmd("let g:go_fmt_command = 'goimports'")
      vim.cmd("au BufRead,BufNewFile *.html set filetype=gohtmltmpl")
      vim.cmd("au BufRead,BufNewFile *.gohtml set filetype=gohtmltmpl")
      -- vim.cmd("au BufRead,BufNewFile *.gohtml set filetype=html")

      -- Detect .tmpl files: strip .tmpl suffix and resolve the underlying filetype
      vim.filetype.add({
        pattern = {
          [".*%.tmpl"] = {
            priority = 10,
            function(path)
              local stem = path:gsub("%.tmpl$", "")
              local basename = vim.fn.fnamemodify(stem, ":t")
              -- Try resolving via the stem's extension
              local ext = basename:match("%.([^%.]+)$")
              if ext then
                local ft = vim.filetype.match({ filename = basename })
                if ft then return ft end
              end
              -- Bare names like Dockerfile.tmpl
              local ft = vim.filetype.match({ filename = basename })
              if ft then return ft end
              -- Fallback: plain text
              return nil
            end,
          },
        },
      })

      -- Highlight {{ ... }} template directives in .tmpl files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "*",
        callback = function(args)
          local bufname = vim.api.nvim_buf_get_name(args.buf)
          if bufname:match("%.tmpl$") then
            vim.api.nvim_set_hl(0, "GoTmplDirective", { fg = "#C678DD", bold = true })
            vim.fn.matchadd("GoTmplDirective", "{{.\\{-}}}", 100)
          end
        end,
      })
    end,
    keys = {
      { "gtc", "<cmd>GoCoverage<cr>", desc = "Go Coverage" },
      { "gtC", "<cmd>GoCoverageClear<cr>", desc = "Go Coverage Clear" },
      { "gtt", "<cmd>GoTest<cr>", desc = "Go Test" },
      { "gtf", "<cmd>GoTestFunc<cr>", desc = "Go Test Func" },
      { "gtF", "<cmd>GoTestFile<cr>", desc = "Go Test File" },
      { "gat", "<cmd>GoAddTags<cr>", desc = "Add Go Tags (json)" },
      { "sgd", "<cmd>split<cr><cmd>GoAddTags<cr>", desc = "Add Go Tags (json)" },
      { "vgd", "<cmd>split<cr><cmd>GoAddTags<cr>", desc = "Add Go Tags (json)" },
      { "gll", "<cmd>GoMetaLinter<cr>", desc = "Golangci-lint" },
    },
  },
}
