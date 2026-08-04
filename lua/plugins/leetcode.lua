-- LeetCode inside nvim. `nvim leetcode` lands on the dashboard (the plugin
-- watches for that arg); in a normal session :Leet loads it on demand.
-- First run: `:Leet cookie update` (paste the leetcode.com session cookie).
-- :Leet run / console execute remotely; for local runs see config/php.lua.

local leet_arg = "leetcode"

return {
  "kawre/leetcode.nvim",
  build = ":TSUpdate html",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  lazy = leet_arg ~= vim.fn.argv(0, -1),
  cmd = "Leet",
  opts = {
    arg = leet_arg,
    lang = "php",
    picker = { provider = "telescope" },
    hooks = {
      -- Hand the screen over to leetcode while it runs (the layout autocmds
      -- would otherwise shred its dashboard/splits); <leader>l takes it back.
      ["enter"] = {
        function()
          require("config.state").leetcode = true
          pcall(function() require("config.blame").close() end)
          pcall(function() require("nvim-tree.api").tree.close() end)
        end,
      },
      ["leave"] = {
        function()
          require("config.state").leetcode = false
        end,
      },
    },
  },
}
