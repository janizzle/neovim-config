-- Global (non-plugin) keymaps. Plugin-local maps live with their plugin
-- (telescope, gitsigns, LSP attach, ...).

-- Buffers ---------------------------------------------------------------------

vim.keymap.set("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })

-- Close the buffer without collapsing its window: save (unless forced), swap
-- a fallback buffer into the window, then delete.
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

vim.keymap.set("n", "<leader>s", "<cmd>update<cr>", { desc = "Save buffer" })
vim.keymap.set("n", "<leader>x", function() smart_close(false) end, { desc = "Save and close buffer" })
vim.keymap.set("n", "<leader>q", function() smart_close(true) end, { desc = "Force close buffer (no save)" })
vim.keymap.set("n", "<leader>X", function() smart_close(true) end, { desc = "Force close buffer (discard changes)" })

-- Windows & buffer tabs by number ---------------------------------------------

-- <leader>w1..9: windows numbered top-left -> bottom-right (1 = tree, 2 = editor).
for i = 1, 9 do
  vim.keymap.set("n", "<leader>w" .. i, i .. "<C-w>w", { desc = "Go to window " .. i })
end

-- <leader>t1..9: Nth bufferline tab, left -> right.
for i = 1, 9 do
  vim.keymap.set("n", "<leader>t" .. i, function()
    require("bufferline").go_to(i, true)
  end, { desc = "Go to buffer tab " .. i })
end

-- Diff & conflicts ------------------------------------------------------------

-- Diffview always opens in its own tabpage; <leader>dq is the way back out.
vim.keymap.set("n", "<leader>dv", "<cmd>DiffviewOpen<cr>",          { desc = "Diff: working changes" })
vim.keymap.set("n", "<leader>dc", "<cmd>DiffviewOpen HEAD~1<cr>",   { desc = "Diff: last commit" })
vim.keymap.set("n", "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", { desc = "Diff: current file history" })
vim.keymap.set("n", "<leader>dH", "<cmd>DiffviewFileHistory<cr>",   { desc = "Diff: repo history" })

-- Close Diffview, close any tabpage that is purely diff windows, and clear
-- diff-mode leftovers (diff turns on scrollbind).
local function diff_close()
  pcall(vim.cmd, "DiffviewClose")
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.api.nvim_tabpage_is_valid(tab) then
      local only_diff = true
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype
        local is_diff = vim.wo[win].diff
          or ft == "DiffviewFiles" or ft == "DiffviewFileHistory"
        if not is_diff then only_diff = false break end
      end
      if only_diff and #vim.api.nvim_list_tabpages() > 1 then
        pcall(vim.cmd, tab .. "tabclose")
      end
    end
  end
  pcall(function() require("config.blame").unbind_all() end)
end
vim.keymap.set("n", "<leader>dq", diff_close, { desc = "Diff: close (+ kill stray diff tab)" })

-- Inline conflicts: git-conflict provides co/ct/cb/c0 + cn/cp in the buffer.
vim.keymap.set("n", "<leader>dx", "<cmd>GitConflictListQf<cr>", { desc = "Merge: list all conflicts (quickfix)" })

-- Terminal --------------------------------------------------------------------

vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], { desc = "Terminal → left window" })
vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], { desc = "Terminal → down window" })
vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], { desc = "Terminal → up window" })
vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], { desc = "Terminal → right window" })
