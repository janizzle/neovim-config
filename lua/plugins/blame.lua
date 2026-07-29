return {
  -- Git blame in a real column to the LEFT of the line numbers (author +
  -- date + short hash per line), so you can see who last changed each line.
  -- Toggle it with <leader>gb; :BlameToggle also works. This is distinct from
  -- gitsigns' <leader>hB, which shows blame as faded virtual text at the end
  -- of the current line only.
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
      -- Keep the cursor in the file you're editing when the blame column
      -- opens. blame.nvim honors this itself (window_view.lua open()), so we
      -- do NOT need to juggle nvim_set_current_win ourselves afterward.
      focus_blame = false,
    })
  end,
}
