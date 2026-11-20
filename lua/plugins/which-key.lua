return {
  -- Pause on a prefix (<space>, g, [, ...) and a popup lists what can follow.
  -- Keys come from each mapping's desc; groups below just name the prefixes.
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    -- Framed like every other float (FloatBorder), not a bare block.
    win = { border = "rounded" },
    spec = {
      { "<leader>b", group = "debug" },
      { "<leader>c", group = "code / changes / claude" },
      { "<leader>d", group = "diff & merge" },
      { "<leader>f", group = "find" },
      { "<leader>g", group = "git" },
      { "<leader>h", group = "hunks" },
      { "<leader>r", group = "rename" },
      { "<leader>t", group = "buffer tabs" },
      { "<leader>v", group = "views" },
      { "<leader>vr", group = "resize (<Esc> to leave)" },
    },
  },
}
