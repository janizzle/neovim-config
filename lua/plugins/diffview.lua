return {
  -- Commit / file-history browsing (2-way layout, stable on nvim 0.12).
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
  config = function()
    require("diffview").setup({ enhanced_diff_hl = true })

    -- The "before" side of an existing file loads from a git object (no
    -- on-disk name), so no filetype is detected and treesitter never
    -- attaches -- plain text on a diff background. Copy the filetype from
    -- the real side onto every diff window and start treesitter there.
    local function color_diff_buffers()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      local ft
      for _, win in ipairs(wins) do
        local f = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if f ~= "" and f ~= "DiffviewFiles" and f ~= "DiffviewFileHistory" then
          ft = f
          break
        end
      end
      if not ft then return end
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local cur = vim.bo[buf].filetype
        if cur == "" or cur == "diff" then
          vim.bo[buf].filetype = ft
          pcall(vim.treesitter.start, buf, ft)
        end
      end
    end

    vim.api.nvim_create_autocmd("User", {
      pattern = { "DiffviewViewEnter", "DiffviewDiffBufWinEnter" },
      callback = function()
        vim.schedule(color_diff_buffers)
      end,
    })
  end,
}
