return {
  -- Debugger (Xdebug); layout, keys and listeners live in config/debug.lua.
  "mfussenegger/nvim-dap",
  event = "VeryLazy",
  dependencies = {
    "mason-org/mason.nvim",
    { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
    -- Values of the variables in scope, shown at the end of each line.
    "theHamsta/nvim-dap-virtual-text",
  },
  config = function()
    require("config.debug").setup()
  end,
}
