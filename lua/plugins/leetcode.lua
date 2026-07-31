-- LeetCode inside nvim. Start a dedicated session with `nvim leetcode` (the
-- `arg` below is what the plugin watches for) to land on the dashboard; in a
-- normal session `:Leet` loads it on demand.
--
-- First run: `:Leet cookie update` to sign in (paste the leetcode.com session
-- cookie from a logged-in browser). Then `:Leet list` / `:Leet daily` to pick a
-- question, `:Leet run` to test, `:Leet submit` to submit.

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
    lang = "python3",
    picker = { provider = "telescope" },
    hooks = {
      -- config/layout.lua rebuilds the tree + welcome layout (with `only`) on
      -- every BufEnter that finds the tree missing, which would shred the
      -- dashboard and the question/description split. Hand the screen over to
      -- leetcode while it's running; <leader>l takes it back.
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
  keys = {
    { "<leader>Lm", "<cmd>Leet<cr>",        desc = "LeetCode: menu" },
    { "<leader>Ll", "<cmd>Leet list<cr>",   desc = "LeetCode: list questions" },
    { "<leader>Ld", "<cmd>Leet daily<cr>",  desc = "LeetCode: daily question" },
    { "<leader>Lr", "<cmd>Leet run<cr>",    desc = "LeetCode: run tests" },
    { "<leader>Ls", "<cmd>Leet submit<cr>", desc = "LeetCode: submit" },
    { "<leader>Lc", "<cmd>Leet console<cr>", desc = "LeetCode: toggle console" },
    { "<leader>Li", "<cmd>Leet desc<cr>",   desc = "LeetCode: toggle description" },
    { "<leader>Lg", "<cmd>Leet lang<cr>",   desc = "LeetCode: change language" },
  },
}
