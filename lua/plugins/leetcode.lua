-- LeetCode inside nvim. Start a dedicated session with `nvim leetcode` (the
-- `arg` below is what the plugin watches for) to land on the dashboard; in a
-- normal session `:Leet` loads it on demand.
--
-- First run: `:Leet cookie update` to sign in (paste the leetcode.com session
-- cookie from a logged-in browser). Then `:Leet list` / `:Leet daily` to pick a
-- question, `:Leet run` to test, `:Leet submit` to submit.
--
-- `:Leet run` / `:Leet console` execute on leetcode.com. To poke at a solution
-- locally instead -- dumping an array mid-craft, say -- see config/php.lua:
-- `:PhpRun`, `:PhpDriver`, `:PhpRepl`.

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
}
