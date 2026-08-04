return {
  -- Git blame in a real column left of the file (author + date + hash per
  -- line); <leader>gb toggles it via the controller in config/blame.lua.
  -- Distinct from gitsigns' <leader>hB (virtual text, current line only).
  "FabijanZulj/blame.nvim",
  cmd = { "BlameToggle" },
  keys = {
    { "<leader>gb", function() require("config.blame").toggle() end, desc = "Toggle git blame column" },
  },
  config = function()
    require("blame").setup({
      date_format = "%d.%m.%Y",
      merge_consecutive = false,
      max_summary_width = 30,
      -- Keep the cursor in the file; the plugin honors this itself, no
      -- window juggling needed afterwards.
      focus_blame = false,
    })
  end,
}
