return {
  -- Commit / file-history browsing, and the merge tool driven by
  -- config/merge.lua (`:Merge`).
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles" },
  config = function()
    local actions = require("diffview.actions")

    -- Opening a plain changed file (two windows) puts the cursor in the left
    -- one instead of diffview's default, the right one. Three-window conflict
    -- layouts are left alone: diffview already lands in the middle there.
    local function focus_left_diff_win()
      local wins = {}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.wo[win].diff then wins[#wins + 1] = win end
      end
      if #wins ~= 2 then return end
      table.sort(wins, function(a, b)
        return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
      end)
      vim.api.nvim_set_current_win(wins[1])
    end

    local function select_entry_left()
      actions.select_entry()
      -- The layout is built asynchronously: focus once it reports in, with a
      -- timer to drop the listener if the same file was already showing.
      local id = vim.api.nvim_create_autocmd("User", {
        pattern = "DiffviewDiffBufWinEnter",
        once = true,
        callback = function() vim.schedule(focus_left_diff_win) end,
      })
      vim.defer_fn(function() pcall(vim.api.nvim_del_autocmd, id) end, 500)
    end

    require("diffview").setup({
      enhanced_diff_hl = true,
      view = {
        default = { layout = "diff2_horizontal", winbar_info = true },
        -- Conflicting files open as three windows side by side:
        --   OURS (HEAD)  |  the working file you edit  |  THEIRS (merged-in).
        -- winbar_info labels each window so the sides can't be mixed up.
        merge_tool = {
          layout = "diff3_horizontal",
          disable_diagnostics = true,
          winbar_info = true,
        },
        file_history = { layout = "diff2_horizontal", winbar_info = true },
      },
      hooks = {
        -- Whole files, not just hunks (like <leader>ds): diff mode folds every
        -- unchanged stretch, file history included.
        diff_buf_win_enter = function(_, winid)
          vim.wo[winid].foldenable = false
        end,
      },
      file_panel = {
        listing_style = "tree",
        win_config = { position = "left", width = 38 },
      },
      -- Same conflict keys as git-conflict.nvim's inline mappings (co/ct/cb/c0,
      -- cn/cp) so the muscle memory carries into the merge tool; the uppercase
      -- variants apply the choice to the whole file. Diffview merges these with
      -- its defaults, so <leader>co & friends keep working too.
      keymaps = {
        file_panel = {
          { "n", "<cr>",          select_entry_left, { desc = "Open file, cursor in the left window" } },
          { "n", "o",             select_entry_left, { desc = "Open file, cursor in the left window" } },
          { "n", "<2-LeftMouse>", select_entry_left, { desc = "Open file, cursor in the left window" } },
        },
        diff3 = {
          { "n", "co", actions.conflict_choose("ours"),       { desc = "Conflict: take OURS" } },
          { "n", "ct", actions.conflict_choose("theirs"),     { desc = "Conflict: take THEIRS" } },
          { "n", "cb", actions.conflict_choose("all"),        { desc = "Conflict: take BOTH" } },
          { "n", "c0", actions.conflict_choose("none"),       { desc = "Conflict: take NEITHER" } },
          { "n", "cO", actions.conflict_choose_all("ours"),   { desc = "Conflict: OURS for the whole file" } },
          { "n", "cT", actions.conflict_choose_all("theirs"), { desc = "Conflict: THEIRS for the whole file" } },
          { "n", "cB", actions.conflict_choose_all("all"),    { desc = "Conflict: BOTH for the whole file" } },
          { "n", "cn", actions.next_conflict,                 { desc = "Conflict: next" } },
          { "n", "cp", actions.prev_conflict,                 { desc = "Conflict: previous" } },
        },
        diff4 = {
          { "n", "co", actions.conflict_choose("ours"),   { desc = "Conflict: take OURS" } },
          { "n", "ct", actions.conflict_choose("theirs"), { desc = "Conflict: take THEIRS" } },
          { "n", "cb", actions.conflict_choose("all"),    { desc = "Conflict: take BOTH" } },
          { "n", "c0", actions.conflict_choose("none"),   { desc = "Conflict: take NEITHER" } },
          { "n", "cn", actions.next_conflict,             { desc = "Conflict: next" } },
          { "n", "cp", actions.prev_conflict,             { desc = "Conflict: previous" } },
        },
      },
    })

    -- The "before" side of an existing file loads from a git object (no
    -- on-disk name), so no filetype is detected and treesitter never
    -- attaches -- plain text on a diff background. Copy the filetype from
    -- the real side onto every diff window and start treesitter there.
    local function color_diff_buffers()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      local ft
      for _, win in ipairs(wins) do
        local f = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if f ~= "" and f ~= "DiffviewFiles" and f ~= "DiffviewFileHistory"
          and f ~= "MergeConflicts"
        then
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
