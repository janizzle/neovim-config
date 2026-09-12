return {
  -- Debugger: Xdebug 3 through vscode-php-debug (mason's php-debug-adapter).
  -- <leader>bc starts listening on 9003; then hit the page / run the CLI with
  -- XDEBUG_SESSION set and execution stops at your breakpoints.
  "mfussenegger/nvim-dap",
  event = "VeryLazy",
  dependencies = {
    "mason-org/mason.nvim",
    { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
  },
  config = function()
    local dap = require("dap")
    local dapui = require("dapui")
    local mason = require("config.mason")

    mason.ensure({ "php-debug-adapter" })

    -- A function, so the binary is looked up per session: on a fresh machine
    -- mason may still be installing it when this config runs.
    dap.adapters.php = function(callback)
      callback({ type = "executable", command = mason.cmd("php-debug-adapter") })
    end
    dap.configurations.php = {
      { type = "php", request = "launch", name = "Listen for Xdebug", port = 9003 },
    }

    -- Panels right and bottom: the file tree already owns the left edge.
    dapui.setup({
      layouts = {
        {
          position = "right",
          size = 50,
          elements = {
            { id = "scopes", size = 0.4 },
            { id = "stacks", size = 0.25 },
            { id = "breakpoints", size = 0.2 },
            { id = "watches", size = 0.15 },
          },
        },
        {
          position = "bottom",
          size = 12,
          elements = { { id = "repl", size = 1 } },
        },
      },
    })
    dap.listeners.after.event_initialized.dapui = dapui.open
    dap.listeners.before.event_terminated.dapui = dapui.close
    dap.listeners.before.event_exited.dapui = dapui.close

    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
    vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError" })
    vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticWarn", linehl = "Visual" })

    local function map(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { desc = "Debug: " .. desc })
    end
    map("<leader>bc", dap.continue, "start / continue")
    map("<leader>bq", dap.terminate, "stop")
    map("<leader>bb", dap.toggle_breakpoint, "toggle breakpoint")
    map("<leader>bB", function() dap.set_breakpoint(vim.fn.input("Condition: ")) end, "conditional breakpoint")
    map("<leader>bo", dap.step_over, "step over")
    map("<leader>bi", dap.step_into, "step into")
    map("<leader>bO", dap.step_out, "step out")
    map("<leader>bu", dapui.toggle, "toggle panels")
  end,
}
