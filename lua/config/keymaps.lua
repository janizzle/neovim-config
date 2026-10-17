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

-- Views -----------------------------------------------------------------------

vim.keymap.set("n", "<leader>vq", "<cmd>close<cr>", { desc = "Close view" })

-- Resizing moves the nearest border in the direction pressed, like tmux:
-- right always pushes a border right, whichever side of it this view is on.
-- (Plain <C-w>> means "this view wider", which in the rightmost view drags
-- its left border left -- backwards on an arrow key.)
local function nudge(dir, step)
  local vertical = dir == "h" or dir == "l"
  local forward = dir == "l" or dir == "j"
  local has_after = vim.fn.winnr(vertical and "l" or "j") ~= vim.fn.winnr()
  local delta = forward == has_after and step or -step
  if vertical then
    vim.api.nvim_win_set_width(0, vim.api.nvim_win_get_width(0) + delta)
  else
    vim.api.nvim_win_set_height(0, vim.api.nvim_win_get_height(0) + delta)
  end
end

-- <C-w> + arrow resizes, then stays in resize mode (shown in the command
-- line): more arrows, with or without another <C-w> in front, keep going.
-- <Esc> leaves; any other key leaves and then does its normal thing.
-- A count multiplies the first step (5<C-w><Right>).
local ARROW_DIRS = { ["<Left>"] = "h", ["<Down>"] = "j", ["<Up>"] = "k", ["<Right>"] = "l" }
local function resize_loop(key)
  local step = vim.v.count1 * 2
  while ARROW_DIRS[key] do
    nudge(ARROW_DIRS[key], step)
    step = 2
    vim.api.nvim_echo({ { "-- RESIZE --", "ModeMsg" }, { "  arrows move the border, <Esc> stops" } }, false, {})
    vim.cmd.redraw()
    local ok, raw = pcall(vim.fn.getcharstr)
    if not ok then break end  -- <C-c>
    key = vim.fn.keytrans(raw)
    if key == "<C-W>" then
      local ok2, nxt = pcall(vim.fn.getcharstr)
      if not ok2 then break end
      raw, key = raw .. nxt, vim.fn.keytrans(nxt)
    end
    if not ARROW_DIRS[key] and key ~= "<Esc>" then
      vim.api.nvim_feedkeys(raw, "mi", false)  -- "i": ahead of keys already queued
    end
  end
  vim.api.nvim_echo({ { "" } }, false, {})
end
for key, dir in pairs(ARROW_DIRS) do
  vim.keymap.set("n", "<C-w>" .. key, function() resize_loop(key) end,
    { desc = "Resize: border " .. dir .. " (repeat arrows, <Esc> stops)" })
end

-- <leader>vh/j/k/l: the same resizing on hjkl, through which-key's loop popup
-- (bare h/j/k/l keep going until <Esc>).
local RESIZE_STEP = 3
local ARROWS = { h = "←", j = "↓", k = "↑", l = "→" }
for dir, arrow in pairs(ARROWS) do
  -- The keys resize mode offers; the loop popup lists them by these descs.
  vim.keymap.set("n", "<leader>vr" .. dir, function() nudge(dir, RESIZE_STEP) end, { desc = "Border " .. arrow })
  vim.keymap.set("n", "<leader>v" .. dir, function()
    nudge(dir, RESIZE_STEP)
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
