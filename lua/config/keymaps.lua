-- Global (non-plugin) keymaps: buffer/window navigation, save/close, terminal
-- escapes, and the diffview/conflict entry points. Plugin-local maps live with
-- their plugin (telescope, gitsigns, LSP attach, ...).

vim.keymap.set("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

local function smart_close(force)
  local buf = vim.api.nvim_get_current_buf()
  if not force
    and vim.bo.modified
    and vim.bo.buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
  then
    vim.cmd("update")
  end
  local fallback
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= buf and vim.bo[b].buflisted and vim.bo[b].buftype == "" then
      fallback = b
      break
    end
  end
  if fallback then
    vim.cmd("buffer " .. fallback)
  else
    vim.cmd("enew")
  end
  pcall(vim.api.nvim_buf_delete, buf, { force = force or false })
end

vim.keymap.set("n", "<leader>x", function() smart_close(false) end, { desc = "Save and close buffer" })
vim.keymap.set("n", "<leader>q", function() smart_close(true) end, { desc = "Force close buffer (no save)" })
vim.keymap.set("n", "<leader>s", "<cmd>update<cr>", { desc = "Save buffer" })
vim.keymap.set("n", "<leader>X", function() smart_close(true) end, { desc = "Force close buffer (discard changes)" })

-- Window switching by number: <leader>w1 .. <leader>w9
-- Windows are numbered top-left -> bottom-right. With the default layout that's
-- roughly: 1 = file tree, 2 = editor.
for i = 1, 9 do
  vim.keymap.set("n", "<leader>w" .. i, i .. "<C-w>w", { desc = "Go to window " .. i })
end

-- Buffer tab switching by number: <leader>t1 .. <leader>t9
-- Jumps to the Nth tab in the bufferline (left -> right).
for i = 1, 9 do
  vim.keymap.set("n", "<leader>t" .. i, function()
    require("bufferline").go_to(i, true)
  end, { desc = "Go to buffer tab " .. i })
end

-- Diffview: commit / file-history browsing (2-way, stable on nvim 0.12).
-- Diffview ALWAYS opens in its own tabpage -- that's the "diff view in a new
-- tab top-right" you were seeing. It isn't opening on its own; it's one of
-- these <leader>d* maps firing (they sit on the same <leader> prefix as gs/gb,
-- so a mistimed chord lands here). Kept, but <leader>dq now force-cleans it.
vim.keymap.set("n", "<leader>dv", "<cmd>DiffviewOpen<cr>",          { desc = "Diff: working changes" })
vim.keymap.set("n", "<leader>dc", "<cmd>DiffviewOpen HEAD~1<cr>",   { desc = "Diff: last commit" })
vim.keymap.set("n", "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", { desc = "Diff: current file history" })
vim.keymap.set("n", "<leader>dH", "<cmd>DiffviewFileHistory<cr>",   { desc = "Diff: repo history" })

-- Close Diffview AND kill any stray diff tab, then land back in the editor.
-- This is the one-key "get me out of the weird diff tab" escape hatch: it
-- closes diffview cleanly, and if a bare diff tabpage somehow lingers it
-- closes that too, so you never get stuck in a tab you didn't mean to open.
local function diff_close()
  pcall(vim.cmd, "DiffviewClose")
  -- Any remaining tab that is purely a diff/diffview view -> close it.
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.api.nvim_tabpage_is_valid(tab) then
      local only_diff = true
      local wins = vim.api.nvim_tabpage_list_wins(tab)
      for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype
        local is_diff = vim.wo[win].diff
          or ft == "DiffviewFiles" or ft == "DiffviewFileHistory"
        if not is_diff then only_diff = false break end
      end
      -- Only close extra tabs, never the last remaining one.
      if only_diff and #vim.api.nvim_list_tabpages() > 1 then
        pcall(vim.cmd, tab .. "tabclose")
      end
    end
  end
  -- Clear any diff-mode leftovers (diff turns on scrollbind too).
  pcall(function() require("config.blame").unbind_all() end)
end
vim.keymap.set("n", "<leader>dq", diff_close, { desc = "Diff: close (+ kill stray diff tab)" })

-- Merge conflicts (inline, single file): just open the conflicted file.
-- git-conflict gives you  co=ours  ct=theirs  cb=both  c0=none  to resolve,
-- and  cn/cp  to jump to the next / prev conflict.
vim.keymap.set("n", "<leader>dx", "<cmd>GitConflictListQf<cr>", { desc = "Merge: list all conflicts (quickfix)" })

vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], { desc = "Terminal → left window" })
vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], { desc = "Terminal → down window" })
vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], { desc = "Terminal → up window" })
vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], { desc = "Terminal → right window" })
