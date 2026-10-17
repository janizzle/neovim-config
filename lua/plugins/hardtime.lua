-- Habit breaker: blocks repeated hjkl/arrow spam and hints at better motions.
-- Toggle with `:Hardtime toggle`, see stats with `:Hardtime report`.

return {
  "m4xshen/hardtime.nvim",
  event = "VeryLazy",
  dependencies = { "MunifTanjim/nui.nvim" },
  opts = {
    -- Once blocked, stay blocked: no time-based reset. A different key starts
    -- a fresh count, so after overshooting with jjj you can still k back.
    -- A count (5j) or an operator (d, y, c, p, ...) also resets the counter.
    max_time = math.huge,
    allow_different_key = true,
    -- Also enforce inside the file tree.
    disabled_filetypes = { NvimTree = false },
  },
}
