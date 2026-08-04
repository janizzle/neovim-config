-- Controller around blame.nvim's <leader>gb / :BlameToggle, fixing two issues:
--
--   1. scrollbind leak: when the blame window disappears by any path other
--      than a clean toggle, its 'scrollbind'/'cursorbind' stay set on the
--      surviving window and every bound window scrolls in lockstep forever.
--   2. stale target: blame binds to whichever window is current on toggle,
--      so it could pin to the tree or a stale buffer.
--
-- Every open/close routes through here: open anchors to the editor window,
-- close strips the bind flags from ALL windows, and entering a different real
-- file auto-closes the blame column.

local M = {}

-- Window/buffer blame was opened on; nil == not open (as far as we know).
M.win = nil
M.buf = nil

local function blame_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "blame" then
      return win
    end
  end
end

-- Safety net for issue #1: however the blame window went away, no window is
-- left glued to another.
local function unbind_all()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    pcall(function()
      vim.wo[win].scrollbind = false
      vim.wo[win].cursorbind = false
    end)
  end
end
M.unbind_all = unbind_all

local function is_real_file(buf)
  return vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype ~= "NvimTree"
    and vim.bo[buf].filetype ~= "blame"
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function editor_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_real_file(vim.api.nvim_win_get_buf(win)) then
      return win
    end
  end
end

function M.close()
  -- Prefer blame.nvim's own teardown so its state resets; fall back to
  -- force-closing any leftover ft=blame window (e.g. after a file was loaded
  -- INTO the blame window the plugin no longer considers itself open).
  local ok = pcall(function()
    if require("blame").is_open() then
      vim.cmd("BlameToggle")
    end
  end)
  if not ok or blame_win() then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "blame" and #vim.api.nvim_tabpage_list_wins(0) > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  unbind_all()
  M.win = nil
  M.buf = nil
end

function M.open()
  -- Anchor to the editor window, not whatever is focused (might be the tree).
  local ew = editor_win()
  if ew and vim.api.nvim_win_is_valid(ew) then
    vim.api.nvim_set_current_win(ew)
  end
  if not is_real_file(vim.api.nvim_get_current_buf()) then
    vim.notify("Blame: put the cursor in a file first", vim.log.levels.WARN)
    return
  end
  M.win = vim.api.nvim_get_current_win()
  M.buf = vim.api.nvim_get_current_buf()
  -- focus_blame=false (plugins/blame.lua) keeps focus in the editor itself.
  pcall(vim.cmd, "BlameToggle")
end

function M.toggle()
  if blame_win() then
    M.close()
  else
    M.open()
  end
end

-- Auto-close when entering a different real file, so blame is never pinned to
-- a stale buffer. Keyed off M.buf, not blame_win(): when a file gets loaded
-- into the blame window that window stops being ft=blame, and blame_win()
-- would miss exactly the broken case. BufEnter (not BufWinEnter) because
-- Telescope/NvimTree entry paths don't fire BufWinEnter reliably.
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)
    if not M.buf then return end
    if not is_real_file(ev.buf) then return end
    if ev.buf == M.buf then return end
    vim.schedule(M.close)
  end,
})

-- Manual escape hatch should scrollbind ever leak from an unforeseen path.
vim.api.nvim_create_user_command("Unbind", unbind_all,
  { desc = "Clear scrollbind/cursorbind on all windows" })

return M
