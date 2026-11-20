-- Global (non-plugin) keymaps. Plugin-local maps live with their plugin
-- (telescope, gitsigns, LSP attach, ...).

-- Insert mode -----------------------------------------------------------------

-- Alt+hjkl moves the cursor without leaving insert mode. On macOS also the
-- characters Option+hjkl types when the terminal doesn't send Alt (see
-- config/alt.lua), so it works without touching iTerm2's settings.
local CURSOR = { h = "<Left>", j = "<Down>", k = "<Up>", l = "<Right>" }
for dir, keys in pairs(require("config.alt").keys) do
  for _, lhs in ipairs(keys) do
    vim.keymap.set("i", lhs, CURSOR[dir], { desc = "Cursor " .. CURSOR[dir]:sub(2, -2):lower() })
  end
end

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

-- Views -----------------------------------------------------------------------

vim.keymap.set("n", "<leader>vq", "<cmd>close<cr>", { desc = "Close view" })

-- <C-w> + arrow moves the nearest border that way and stays in resize mode
-- (more arrows keep going, <Esc> stops). See config/resize.lua.
local resize = require("config.resize")
for key, dir in pairs(resize.ARROW_DIRS) do
  vim.keymap.set("n", "<C-w>" .. key, function() resize.loop(key) end,
    { desc = "Resize: border " .. dir .. " (repeat arrows, <Esc> stops)" })
end

-- <leader>vh/j/k/l: the same resizing on hjkl, through which-key's loop popup
-- (bare h/j/k/l keep going until <Esc>).
local RESIZE_STEP = 3
local ARROWS = { h = "←", j = "↓", k = "↑", l = "→" }
for dir, arrow in pairs(ARROWS) do
  -- The keys resize mode offers; the loop popup lists them by these descs.
  vim.keymap.set("n", "<leader>vr" .. dir, function() resize.nudge(dir, RESIZE_STEP) end, { desc = "Border " .. arrow })
  vim.keymap.set("n", "<leader>v" .. dir, function()
    resize.nudge(dir, RESIZE_STEP)
    require("which-key").show({ keys = "<leader>vr", loop = true })
  end, { desc = "Resize view " .. arrow .. " (then hjkl, <Esc> done)" })
end
vim.keymap.set("n", "<leader>vr=", "<cmd>wincmd =<cr>", { desc = "Equalize views" })

-- Buffer tabs by number -------------------------------------------------------

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
vim.keymap.set("n", "<leader>gs", "<cmd>Merge<cr>", { desc = "Merge: resolve conflicts (diffview)" })

-- Same as <leader>l: close every diff view and go home with the file you
-- were on open as a plain file. See config/layout.lua.
vim.keymap.set("n", "<leader>dq", function() require("config.layout").home() end,
  { desc = "Diff: close all diff views (= restore layout, <leader>l)" })

-- Inline conflicts: git-conflict provides co/ct/cb/c0 + cn/cp in the buffer.
vim.keymap.set("n", "<leader>dx", "<cmd>GitConflictListQf<cr>", { desc = "Merge: list all conflicts (quickfix)" })

-- Terminal: <Esc>, <C-q>, :Term and the window keys live in config/term.lua.
