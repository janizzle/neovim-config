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
-- The one exception is diffview's history list, which sits along the bottom:
-- it is still window 1, so w1 is the list in every view.
local function numbered_windows()
  local wins, list = {}, {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then   -- skip floats
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "DiffviewFileHistory" then
        list[#list + 1] = win
      else
        wins[#wins + 1] = win
      end
    end
  end
  return vim.list_extend(list, wins)
end

for i = 1, 9 do
  vim.keymap.set("n", "<leader>w" .. i, function()
    local win = numbered_windows()[i]
    if win then vim.api.nvim_set_current_win(win) end
  end, { desc = "Go to window " .. i })
end

-- <leader>t1..9: Nth bufferline tab, left -> right.
for i = 1, 9 do
  vim.keymap.set("n", "<leader>t" .. i, function()
    require("bufferline").go_to(i, true)
  end, { desc = "Go to buffer tab " .. i })
end

-- Diff & conflicts ------------------------------------------------------------

-- This file, side by side, in place: your buffer stays on the left, the
-- committed version opens on the right. See config/sidediff.lua.
vim.keymap.set("n", "<leader>ds", function() require("config.sidediff").toggle() end,
  { desc = "Diff: this file vs HEAD, side by side (toggle)" })

-- Every change since HEAD: tree of changed files on the left, then your
-- working copy | the committed file. See config/review.lua.
vim.keymap.set("n", "<leader>dd", function() require("config.review").open() end,
  { desc = "Diff: review changes (working tree | HEAD)" })

-- Diffview always opens in its own tabpage; <leader>dq is the way back out.
vim.keymap.set("n", "<leader>dv", "<cmd>DiffviewOpen<cr>",          { desc = "Diff: working changes" })
vim.keymap.set("n", "<leader>dc", "<cmd>DiffviewOpen HEAD~1<cr>",   { desc = "Diff: last commit" })
vim.keymap.set("n", "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", { desc = "Diff: current file history" })
vim.keymap.set("n", "<leader>dH", "<cmd>DiffviewFileHistory<cr>",   { desc = "Diff: repo history" })

-- Merge workspace: conflict list + changed files on the left, OURS | working |
-- THEIRS side by side. See config/merge.lua.
vim.keymap.set("n", "<leader>dm", "<cmd>Merge<cr>", { desc = "Merge: resolve conflicts (diffview)" })

-- Same as <leader>l: close every diff view and go home with the file you
-- were on open as a plain file. See config/layout.lua.
vim.keymap.set("n", "<leader>dq", function() require("config.layout").home() end,
  { desc = "Diff: close all diff views (= restore layout, <leader>l)" })

-- Inline conflicts: git-conflict provides co/ct/cb/c0 + cn/cp in the buffer.
vim.keymap.set("n", "<leader>dx", "<cmd>GitConflictListQf<cr>", { desc = "Merge: list all conflicts (quickfix)" })

-- Terminal --------------------------------------------------------------------

vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], { desc = "Terminal → left window" })
vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], { desc = "Terminal → down window" })
vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], { desc = "Terminal → up window" })
vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], { desc = "Terminal → right window" })

-- :terminal opens in a split at the bottom instead of taking over the window.
vim.api.nvim_create_user_command("Term", function(o)
  vim.cmd("botright 15split")
  vim.cmd("terminal " .. o.args)
  vim.cmd("startinsert")
end, { nargs = "*", complete = "shellcmd", desc = ":terminal in a bottom split" })

for _, name in ipairs({ "terminal", "term" }) do
  vim.cmd(([[cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? 'Term' : '%s']]):format(name, name, name))
end
