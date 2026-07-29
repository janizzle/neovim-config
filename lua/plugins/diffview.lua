return {
  -- Commit / file-history browsing (2-way layout, stable on nvim 0.12).
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
  config = function()
    require("diffview").setup({ enhanced_diff_hl = true })

    -- Syntax coloring in the diff panels. A NEW file's diff buffer already
    -- gets a filetype (nvim reads its extension), so treesitter attaches and
    -- it's colored. An EXISTING file's "before" side is loaded straight from
    -- a git object (a buffer with no on-disk name), so nvim never detects a
    -- filetype -- treesitter can't attach and only the diff background shows,
    -- no syntax. Copy the filetype from the real ("after") side onto every
    -- diff window in the view and (re)start treesitter there, so modified
    -- files are colored exactly like new ones.
    local function color_diff_buffers()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      local ft
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local f = vim.bo[buf].filetype
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
