return {
  -- Thin vertical line-length ruler: draws a slim "│" at column 120 instead
  -- of the full-cell colorcolumn block. Color set via the VirtColumn group.
  "lukas-reineke/virt-column.nvim",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    char = "│",
    virtcolumn = "120",
    highlight = "VirtColumn",
  },
}
