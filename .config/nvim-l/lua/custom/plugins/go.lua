return {
  {
    "fatih/vim-go",
    lazy = false,
    init = function()
      -- On every new install need to run GoInstallBinaries
      vim.cmd("let g:go_gocode_autobuild=0")
      vim.cmd("let g:go_fmt_command = 'goimports'")
      vim.cmd("au BufRead,BufNewFile *.html set filetype=gohtmltmpl")
      vim.cmd("au BufRead,BufNewFile *.gohtml set filetype=gohtmltmpl")
      -- vim.cmd("au BufRead,BufNewFile *.gohtml set filetype=html")
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
