return {
  -- Editing helpers from mini.nvim: auto-closing pairs, surround (sa / sd /
  -- sr) and extra a/i textobjects -- af/if function, ac/ic class.
  "nvim-mini/mini.nvim",
  version = false,
  dependencies = {
    -- Only its textobjects queries (runtime files); nothing to set up.
    { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
  },
  config = function()
    require("mini.pairs").setup()
    require("mini.surround").setup()

    local ai = require("mini.ai")
    ai.setup({
      n_lines = 500,   -- reach a whole class body, not just nearby lines
      custom_textobjects = {
        f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
        c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
      },
    })
  end,
}
