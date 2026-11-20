-- Motion hints: virtual text showing where w/b/e/^/$ etc. would land on the
-- current line, plus gutter hints for gg/G/{/}. Toggle with `:Precognition toggle`.

return {
  "tris203/precognition.nvim",
  event = "VeryLazy",
  opts = {
    startVisible = true,
  },
  config = function(_, opts)
    -- To place its hints, precognition tries every motion for real in a
    -- scratch buffer, and doing that from visual mode drops to normal mode
    -- and straight back. Nobody should hear about that flicker: which-key
    -- takes the ModeChanged for a real one and abandons the <leader> sequence
    -- it is reading, so <leader>cy on a selection fell through to a plain `y`
    -- whenever a hint redraw landed between the keys. Every redraw builds its
    -- hints here, so ignoring ModeChanged for just this keeps both working.
    local HintPlan = require("precognition.hint_plan")
    local build = HintPlan.build
    HintPlan.build = function(...)
      local saved = vim.o.eventignore
      vim.o.eventignore = saved == "" and "ModeChanged" or (saved .. ",ModeChanged")
      local ok, plan = pcall(build, ...)
      vim.o.eventignore = saved
      if not ok then error(plan, 0) end
      return plan
    end

    require("precognition").setup(opts)
  end,
}
