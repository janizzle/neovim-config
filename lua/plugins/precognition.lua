-- Motion hints: virtual text showing where w/b/e/^/$ etc. would land on the
-- current line, plus gutter hints for gg/G/{/}. Toggle with `:Precognition toggle`.

return {
  "tris203/precognition.nvim",
  event = "VeryLazy",
  opts = {
    startVisible = true,
  },
}
