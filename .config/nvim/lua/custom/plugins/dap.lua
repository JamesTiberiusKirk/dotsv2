-- Disabling for now because kickstart comes with a builtin config for dap under kickstart/plugins/debug.lua
if true then
  return {}
end

return {
  {
    "rcarriga/nvim-dap-ui",
    init = function()
      require("dapui").setup()
    end
  },
  {
    "mfussenegger/nvim-dap",
    init = function ()
      local dap = require("dap")
      -- dap.adapters.delve = {
      --   type = 'server',
      --   port = '${port}',
      --   executable = {
      --     command = 'dlv',
      --     args = {'dap', '-l', '127.0.0.1:${port}'},
      --   }
      -- }
      dap.adapters.delve = {
        type = 'server',
        port = 12345,
        executable = {
          command = 'dlv',
          args = {'dap', '-l', '127.0.0.1:12345'},
        }
      }
      -- dap.adapters.delve = {
      --     type = "server",
      --     host = "127.0.0.1",
      --     port = 12345,
      -- }

      -- https://github.com/go-delve/delve/blob/master/Documentation/usage/dlv_dap.md
      dap.configurations.go = {
        {
          type = "delve",
          name = "Debug",
          request = "launch",
          program = "${file}"
        },
        {
          type = "delve",
          name = "Debug test", -- configuration for debugging test files
          request = "launch",
          mode = "test",
          program = "${file}"
        },
        -- works with go.mod packages and sub packages 
        {
          type = "delve",
          name = "Debug test (go.mod)",
          request = "launch",
          mode = "test",
          program = "./${relativeFileDirname}"
        },
      }

    end
  },
}
