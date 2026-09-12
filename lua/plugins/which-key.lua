return {
  -- Pause on a prefix (<space>, g, [, ...) and a popup lists what can follow.
  -- Keys come from each mapping's desc; groups below just name the prefixes.
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    spec = {
      { "<leader>b", group = "debug" },
      { "<leader>c", group = "code / changes" },
      { "<leader>d", group = "diff & merge" },
      { "<leader>f", group = "find" },
      { "<leader>g", group = "git" },
      { "<leader>h", group = "hunks" },
      { "<leader>r", group = "rename" },
      { "<leader>t", group = "buffer tabs" },
      { "<leader>w", group = "windows" },
    },
  },
}
