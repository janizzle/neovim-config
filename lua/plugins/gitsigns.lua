return {
  "lewis6991/gitsigns.nvim",
  config = function()
    local gs = require("gitsigns")

    -- One color language for change marking: blue = added/changed (gutter,
    -- line numbers, translucent inline word-diff), red = removed. Without
    -- this, word_diff links to the hard diff backgrounds. Reapplied on
    -- ColorScheme.
    local function gitsigns_marking_colors()
      local hl = vim.api.nvim_set_hl
      local blue = "#61AFEF"
      local red  = "#7a3b48"
      hl(0, "GitSignsAddInline",    { bg = "#22384f" })
      hl(0, "GitSignsChangeInline", { bg = "#22384f" })
      hl(0, "GitSignsDeleteInline", { bg = "#22384f" })
      hl(0, "GitSignsAddNr",    { fg = blue })
      hl(0, "GitSignsChangeNr", { fg = blue })
      hl(0, "GitSignsDeleteNr", { fg = red })
      hl(0, "GitSignsAdd",          { fg = blue })
      hl(0, "GitSignsChange",       { fg = blue })
      hl(0, "GitSignsChangedelete", { fg = blue })
      hl(0, "GitSignsTopdelete",    { fg = red })
      hl(0, "GitSignsDelete",       { fg = red })
      hl(0, "GitSignsUntracked",    { fg = blue })
    end
    gitsigns_marking_colors()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = gitsigns_marking_colors })

    gs.setup({
      signcolumn = true,   -- gutter markers
      numhl      = true,   -- tint changed line numbers
      linehl     = false,  -- whole-line highlight (toggle with <leader>hL)
      word_diff  = true,   -- mark the exact changed chars inline
      on_attach = function(bufnr)
        local function map(l, r, desc)
          vim.keymap.set("n", l, r, { buffer = bufnr, desc = desc })
        end
        -- ]c/[c are vim-standard but need AltGr on Swiss QWERTZ; <leader>cn/cp
        -- mirror the cn/cp conflict keys as an AltGr-free alternative.
        map("]c", function() gs.nav_hunk("next") end, "Next change")
        map("[c", function() gs.nav_hunk("prev") end, "Prev change")
        map("<leader>cn", function() gs.nav_hunk("next") end, "Next changed line")
        map("<leader>cp", function() gs.nav_hunk("prev") end, "Prev changed line")
        map("<leader>hp", gs.preview_hunk, "Preview hunk (float)")
        map("<leader>hi", gs.preview_hunk_inline, "Preview hunk (inline)")
        map("<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("<leader>hs", gs.stage_hunk, "Stage (merge) hunk")
        map("<leader>hr", gs.reset_hunk, "Reset (discard) hunk")
        map("<leader>hS", gs.stage_buffer, "Stage whole file")
        map("<leader>hR", gs.reset_buffer, "Reset whole file")
        map("<leader>hw", gs.toggle_word_diff, "Toggle inline word diff")
        map("<leader>hL", gs.toggle_linehl, "Toggle line highlight")
        map("<leader>hB", gs.toggle_current_line_blame, "Toggle inline blame")
      end,
    })
  end,
}
