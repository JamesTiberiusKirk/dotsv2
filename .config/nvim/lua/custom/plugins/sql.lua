return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        sql = { "sql_align_format" },
      },
      format_on_save = {
        timeout_ms = 2000,
        lsp_fallback = false,
      },
      formatters = {
        sql_align_format = {
          command = "sql-align-format",
          stdin = true,
        },
      },
    },
  },
}
