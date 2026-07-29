-- Controller around blame.nvim's <leader>gb / :BlameToggle.
--
-- blame.nvim opens a narrow blame column in a vertical split and keeps it in
-- sync with the file by turning ON 'scrollbind' and 'cursorbind' in both
-- windows. Two things about that were causing the "funky shit":
--
--   1. scrollbind LEAK. When the blame window went away by any path other than
--      a clean :BlameToggle (you opened another file into the editor window,
--      the layout autocmds rearranged windows, you closed a split), the
--      'scrollbind'/'cursorbind' flags were left set on the surviving window.
--      From then on every window that also had scrollbind (the tree, other
--      splits) scrolled in lockstep -- and it "persisted after closing"
--      because nothing ever cleared the flag.
--
--   2. FOCUS / stale target. blame binds to whatever window was current when
--      you toggled it. Open a new file (which, via the layout code, may land
--      in a different window) and the blame column is now pinned to the wrong
--      buffer -- so it "gets confused", the cursor stays parked in the blame
--      pane, and a redraw can paint blame content where you didn't expect it.
--
-- Fix: route every open/close through here. We remember which window blame is
-- attached to, force the cursor back into the editor after opening, strip
-- scroll/cursorbind from ALL windows on close, and -- per the chosen behavior
-- -- auto-close the blame column the moment you enter a different real file.

local M = {}

-- Window that owned the file when blame was opened, and the buffer it is
-- showing blame for. nil == blame not open (as far as we're concerned).
M.win = nil
M.buf = nil

-- Is a blame column currently present anywhere in this tabpage?
local function blame_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "blame" then
      return win
    end
  end
end

-- Clear the scroll/cursor lockstep flags everywhere. This is the safety net
-- for symptom #1: no matter how the blame window disappeared, no window is
-- left glued to another afterwards.
local function unbind_all()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    pcall(function()
      vim.wo[win].scrollbind = false
      vim.wo[win].cursorbind = false
    end)
  end
end
M.unbind_all = unbind_all

-- Is `buf` a normal, on-disk file buffer (not the tree, not blame, not a
-- terminal/help/quickfix/prompt)?
local function is_real_file(buf)
  return vim.bo[buf].buftype == ""
    and vim.bo[buf].filetype ~= "NvimTree"
    and vim.bo[buf].filetype ~= "blame"
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

--- The editor window: first window in the tab holding a real file buffer.
local function editor_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_real_file(vim.api.nvim_win_get_buf(win)) then
      return win
    end
  end
end

function M.close()
  -- Prefer blame.nvim's own teardown so its internal state is reset. Fall back
  -- to force-closing any leftover ft=blame window if the toggle no-ops (e.g. a
  -- file got loaded INTO the blame window, so the plugin no longer thinks it's
  -- open but a stray narrow window is still hanging around).
  local ok = pcall(function()
    if require("blame").is_open() then
      vim.cmd("BlameToggle")
    end
  end)
  if not ok or blame_win() then
    -- Nuke any window still showing a blame buffer.
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "blame" and #vim.api.nvim_tabpage_list_wins(0) > 1 then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  -- Whether or not the toggle found a window, scrub the bind flags: this is
  -- the line that actually cures the "everything scrolls together" bug.
  unbind_all()
  M.win = nil
  M.buf = nil
end

function M.open()
  -- Anchor blame to the actual editor window/buffer, not to whatever happens
  -- to be focused (which might be the tree). This is symptom #2's fix.
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
  pcall(vim.cmd, "BlameToggle")
  -- blame.nvim keeps focus in the editor window itself when focus_blame=false
  -- (set in plugins/blame.lua). No manual nvim_set_current_win needed here --
  -- doing it ourselves was fighting the plugin and losing.
end

function M.toggle()
  if blame_win() then
    M.close()
  else
    M.open()
  end
end

-- Auto-close blame the moment you enter a different real file (the chosen
-- behavior). Opening a file closes the blame column and drops you back in the
-- editor -- so blame can never end up pinned to a stale buffer.
--
-- BufEnter (not BufWinEnter): files opened from Telescope reuse the current
-- window and from NvimTree land with transient focus, neither of which fires
-- BufWinEnter reliably. BufEnter fires whenever you actually land in a buffer,
-- so it catches both entry paths.
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(ev)
    -- Key off OUR state (M.buf), not blame_win(). When a file gets loaded into
    -- the blame window itself, that window stops being ft=blame, so blame_win()
    -- would return nil and we'd never clean up -- which is exactly the broken
    -- case. M.buf stays set until we tear down, so we always react.
    if not M.buf then return end
    if not is_real_file(ev.buf) then return end
    if ev.buf == M.buf then
      return  -- same file blame was opened on; leave it be
    end
    vim.schedule(M.close)
  end,
})

-- Manual escape hatch: if scrollbind ever leaks again from some path we didn't
-- foresee, :Unbind clears it instantly.
vim.api.nvim_create_user_command("Unbind", unbind_all,
  { desc = "Clear scrollbind/cursorbind on all windows" })

return M
