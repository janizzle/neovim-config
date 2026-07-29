return {
  "lewis6991/gitsigns.nvim",
  config = function()
    local gs = require("gitsigns")

    -- Tone down the in-buffer change marking. `word_diff = true` otherwise
    -- links its inline groups to the diff backgrounds (a hard, washed-out
    -- block); instead paint the changed chars in a light, transparent blue.
    -- The CHANGED LINE NUMBERS and the add/change gutter markers are the same
    -- bright blue as the in-buffer change marker; only DELETE stays red.
    -- Reapplied on ColorScheme so it survives reloads.
    local function gitsigns_marking_colors()
      local hl = vim.api.nvim_set_hl
      local blue = "#61AFEF"   -- change marker blue (matches palette C.func)
      local red  = "#7a3b48"   -- delete red (matches DiffDelete fg)
      -- Inline word-diff in the buffer: subtle, translucent light blue.
      hl(0, "GitSignsAddInline",    { bg = "#22384f" })
      hl(0, "GitSignsChangeInline", { bg = "#22384f" })
      hl(0, "GitSignsDeleteInline", { bg = "#22384f" })
      -- Changed line numbers: blue (delete = red).
      hl(0, "GitSignsAddNr",    { fg = blue })
      hl(0, "GitSignsChangeNr", { fg = blue })
      hl(0, "GitSignsDeleteNr", { fg = red })
      -- Gutter sign column (the marker left of the number): add/change blue,
      -- delete red -- so red always means "removed", blue means "added/changed".
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
      signcolumn = true,   -- gutter markers for +/~/-
      numhl      = true,   -- tint the line number of changed lines (magenta)
      linehl     = false,  -- whole-line highlight (toggle with <leader>hL)
      word_diff  = true,   -- mark the exact changed chars inline in the buffer
      on_attach = function(bufnr)
        local function map(l, r, desc)
          vim.keymap.set("n", l, r, { buffer = bufnr, desc = desc })
        end
        -- jump between changed hunks. ]c / [c are the vim-standard keys but
        -- ] and [ need AltGr on a Swiss QWERTZ keyboard, so <leader>cn / <leader>cp
        -- mirror the cn/cp conflict-navigation keys as an AltGr-free alternative.
        map("]c", function() gs.nav_hunk("next") end, "Next change")
        map("[c", function() gs.nav_hunk("prev") end, "Prev change")
        map("<leader>cn", function() gs.nav_hunk("next") end, "Next changed line")
        map("<leader>cp", function() gs.nav_hunk("prev") end, "Prev changed line")
        -- inspect a change
        map("<leader>hp", gs.preview_hunk, "Preview hunk (float)")
        map("<leader>hi", gs.preview_hunk_inline, "Preview hunk (inline)")
        map("<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
        -- cherry-pick / merge individual changes into or out of the index
        map("<leader>hs", gs.stage_hunk, "Stage (merge) hunk")
        map("<leader>hr", gs.reset_hunk, "Reset (discard) hunk")
        map("<leader>hS", gs.stage_buffer, "Stage whole file")
        map("<leader>hR", gs.reset_buffer, "Reset whole file")
        -- toggle the inline marking
        map("<leader>hw", gs.toggle_word_diff, "Toggle inline word diff")
        map("<leader>hL", gs.toggle_linehl, "Toggle line highlight")
        map("<leader>hB", gs.toggle_current_line_blame, "Toggle inline blame")
      end,
    })
  end,
}
