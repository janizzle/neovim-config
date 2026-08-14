-- "What did I change in this file?", side by side, without leaving the file.
--
--   +-----------------------------+-----------------------------+
--   |  WORKING TREE               |  HEAD                       |
--   |  your buffer, edits and all |  the file as last committed  |
--   +-----------------------------+-----------------------------+
--
-- Diffview answers the same question, but it takes over a tabpage and puts the
-- old text on the left. Here the buffer you are editing keeps its window and
-- stays on the left, where you were already reading it, and the committed text
-- opens beside it on the right. <leader>ds toggles it.
--
-- The right pane is a scratch buffer, not the file: it can never be written,
-- and closing it can never lose an edit.

local api = vim.api

local M = {}

-- One at a time, like the blame column: two of these side by side is four
-- scroll-bound windows and no room left to read any of them.
local view = { win = nil, buf = nil, src_win = nil, src_buf = nil }

local function git(args)
  local out = vim.fn.systemlist(vim.list_extend({ "git" }, args))
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function is_real_file(buf)
  return api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ""
    and api.nvim_buf_get_name(buf) ~= ""
end

--- The window holding a real file: the cursor may well be in the tree.
local function editor_win()
  if is_real_file(api.nvim_get_current_buf()) then return api.nvim_get_current_win() end
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_real_file(api.nvim_win_get_buf(win)) then return win end
  end
end

--- The committed text of `abs`, plus the label to put over it. Falls back to
--- the index for a file that is staged but not yet in HEAD, so a newly added
--- file still diffs against something rather than refusing to open.
local function committed(abs)
  -- --show-prefix rather than trimming the repo root off the absolute path: the
  -- two disagree as soon as anything in the path is a symlink.
  local dir = vim.fn.fnamemodify(abs, ":h")
  local prefix = git({ "-C", dir, "rev-parse", "--show-prefix" })
  if not prefix then return end

  local rel = (prefix[1] or "") .. vim.fn.fnamemodify(abs, ":t")
  local head = git({ "-C", dir, "show", "HEAD:" .. rel })
  if head then return head, "HEAD" end

  local index = git({ "-C", dir, "show", ":" .. rel })
  if index then return index, "INDEX" end
end

local function winbar(group, text)
  return ("%%#%s# %s %%#DiffSideWinbarFill#"):format(group, (text:gsub("%%", "%%%%")))
end

function M.close()
  local win, buf, src = view.win, view.buf, view.src_win
  view = { win = nil, buf = nil, src_win = nil, src_buf = nil }

  if win and api.nvim_win_is_valid(win) and #api.nvim_tabpage_list_wins(0) > 1 then
    pcall(api.nvim_win_close, win, true)
  end
  if buf and api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  -- diffoff leaves scrollbind and the diff foldmethod behind on the surviving
  -- window if it is skipped, and a window glued to nothing is worse than no
  -- diff at all.
  if src and api.nvim_win_is_valid(src) then
    api.nvim_win_call(src, function() vim.cmd("diffoff") end)
    vim.wo[src].winbar = ""
  end
end

function M.open()
  local src_win = editor_win()
  if not src_win then
    vim.notify("Diff: put the cursor in a file first", vim.log.levels.WARN)
    return
  end
  api.nvim_set_current_win(src_win)

  local src_buf = api.nvim_win_get_buf(src_win)
  local abs = api.nvim_buf_get_name(src_buf)

  local old, rev = committed(abs)
  if not old then
    vim.notify("Diff: " .. vim.fn.fnamemodify(abs, ":t") .. " is not in git yet", vim.log.levels.WARN)
    return
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, old)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  -- Same filetype as the file, so the old side is syntax-coloured too --
  -- otherwise half the diff is plain text and only one side is readable.
  local ft = vim.bo[src_buf].filetype
  if ft ~= "" then
    vim.bo[buf].filetype = ft
    pcall(vim.treesitter.start, buf, ft)
  end
  pcall(api.nvim_buf_set_name, buf, ("%s @ %s"):format(abs, rev))

  vim.keymap.set("n", "q", M.close, { buffer = buf, nowait = true, silent = true,
    desc = "Diff: close the side-by-side view" })

  -- rightbelow: the old text goes to the right of the file, never in front of
  -- it. nvim_win_call restores the focused window afterwards, so grab the new
  -- window's handle while we are still inside.
  local win
  api.nvim_win_call(src_win, function()
    vim.cmd("rightbelow vsplit")
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
  end)

  view = { win = win, buf = buf, src_win = src_win, src_buf = src_buf }

  for _, w in ipairs({ src_win, win }) do
    api.nvim_win_call(w, function() vim.cmd("diffthis") end)
    vim.wo[w].list = false
  end
  vim.wo[src_win].winbar = winbar("DiffSideWinbarNew", "WORKING TREE · " .. vim.fn.fnamemodify(abs, ":t"))
  vim.wo[win].winbar = winbar("DiffSideWinbarOld", rev .. " · as committed")

  -- Read and edit on the left; the right pane is only there to be looked at.
  api.nvim_set_current_win(src_win)
end

function M.toggle()
  if view.win and api.nvim_win_is_valid(view.win) then
    M.close()
  else
    M.open()
  end
end

function M.is_open()
  return view.win ~= nil and api.nvim_win_is_valid(view.win)
end

local augroup = api.nvim_create_augroup("SideDiff", { clear = true })

-- Closing either window by hand (:q, <C-w>c) has to tear down the other half,
-- or the file is left in diff mode and scroll-bound to a window that is gone.
api.nvim_create_autocmd("WinClosed", {
  group = augroup,
  callback = function(ev)
    local closed = tonumber(ev.match)
    if not (view.win and (closed == view.win or closed == view.src_win)) then return end
    if closed == view.win then view.win = nil end
    if closed == view.src_win then view.src_win = nil end
    vim.schedule(M.close)
  end,
})

-- Following a definition or a telescope pick into another file would leave the
-- diff pinned to a buffer you can no longer see. The scratch pane is buftype
-- nofile, so entering it is not "another file" and doesn't trip this.
api.nvim_create_autocmd("BufEnter", {
  group = augroup,
  callback = function(ev)
    if not (view.src_buf and M.is_open()) then return end
    if ev.buf == view.src_buf or not is_real_file(ev.buf) then return end
    vim.schedule(M.close)
  end,
})

api.nvim_create_user_command("DiffSide", M.toggle,
  { desc = "Toggle the working tree | HEAD side-by-side view of this file" })

return M
