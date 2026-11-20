-- Startup layout: file tree on the left, welcome screen in the main window,
-- kept intact by autocmds; restore on demand with <leader>l / :Layout.

local state = require("config.state")
local welcome = require("welcome")

local function ensure_normal_buffer()
  if vim.bo.buftype == "" and vim.bo.filetype ~= "NvimTree" then
    return
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buflisted
      and vim.bo[buf].buftype == ""
      and vim.bo[buf].filetype ~= "NvimTree"
    then
      vim.api.nvim_set_current_buf(buf)
      return
    end
  end
  vim.cmd("enew")
end

-- Going home from a diff -------------------------------------------------------

local function is_plain_file(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.bo[buf].buftype == ""
    and name ~= ""
    and not name:match("^%a[%w+.-]*://")   -- diffview://, fugitive://, ...
    and vim.bo[buf].filetype ~= "NvimTree"
end

--- The file you were looking at, to reopen as a plain file once the diff views
--- are gone: the window you are in, else the file diffview has selected (in a
--- history view both panes are old revisions), else any real file on screen.
--- @return integer|string|nil buffer, or an absolute path
local function file_in_view()
  local cur = vim.api.nvim_get_current_buf()
  if is_plain_file(cur) then return cur end

  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if view then
    local file = view.cur_entry
      or (view.panel and view.panel.cur_item and view.panel.cur_item[2])
    local abs = file and file.absolute_path
    if abs and vim.fn.filereadable(abs) == 1 then return abs end
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_plain_file(buf) then return buf end
  end
end

--- Close every <leader>d view (diffview tabs, the merge workspace, the
--- side-by-side diff), the blame column and any other tabpage, and give the
--- merge result buffers back as plain files.
local function close_diff_views()
  pcall(function() require("config.merge").close_panel() end)
  pcall(function() require("config.sidediff").close() end)
  pcall(function() require("config.blame").close() end)

  -- Only if diffview ever loaded: requiring it here would load the plugin on
  -- every <leader>l.
  local lib = package.loaded["diffview.lib"]
  if lib then
    for _ = 1, 20 do
      local view = lib.views[1]
      if not view then break end
      if view.tabpage and vim.api.nvim_tabpage_is_valid(view.tabpage) then
        vim.api.nvim_set_current_tabpage(view.tabpage)
        pcall(vim.cmd, "DiffviewClose")
      end
      if lib.views[1] == view then pcall(lib.dispose_view, view) end
    end
  end

  pcall(function() require("config.mergeresult").detach_all() end)
  if #vim.api.nvim_list_tabpages() > 1 then pcall(vim.cmd, "tabonly") end
end

--- A window that showed a buffer inside a diff hands its options back the next
--- time that buffer is displayed -- the merge pane's winbar and colours, diff
--- mode, folds, scroll binding. Put them all back to the global defaults, along
--- with anything a side panel may have left on the window we keep.
local function plain_window(win)
  vim.api.nvim_win_call(win, function()
    if vim.wo.diff then vim.cmd("diffoff") end
    vim.wo.winfixbuf = false
    vim.cmd("setlocal winbar< winhighlight< scrollbind< cursorbind< foldenable< foldmethod< foldcolumn< signcolumn<"
      .. " winfixwidth< winfixheight< number< relativenumber< cursorline< statuscolumn< spell< wrap<")
  end)
  -- Re-run the `list` normalizer from config/options.lua for this window.
  vim.api.nvim_exec_autocmds("BufWinEnter",
    { buffer = vim.api.nvim_win_get_buf(win), modeline = false })
end

-- Side panels -------------------------------------------------------------------

local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
end

--- Debugger panels showing in this tabpage (dap-ui's elements, the REPL).
local function debug_panels_open()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if ft:match("^dapui_") or ft == "dap-repl" then return true end
  end
  return false
end

--- Close the debugger panels and the file tree through their own APIs.
--- `:only` alone would take their windows away behind their backs: dap-ui
--- keeps forcing its buffers into windows it still thinks it owns (so a debug
--- panel ends up as the "main" window), and nvim-tree keeps believing it is
--- open (so the tree never comes back). Terminals need nothing: `:only` just
--- hides them, and they keep running.
local function close_panels()
  if package.loaded["dapui"] then pcall(require("dapui").close) end
  if package.loaded["dap"] then pcall(function() require("dap").repl.close() end) end
  if package.loaded["nvim-tree"] then
    pcall(function() require("nvim-tree.api").tree.close_in_all_tabs() end)
  end
end

--- The window to keep: the current one if it holds a file (or the welcome
--- screen), else any that does, else a new one.
local function main_window()
  local function usable(win)
    if not vim.api.nvim_win_is_valid(win) or is_float(win) then return false end
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "NvimTree"
  end
  local cur = vim.api.nvim_get_current_win()
  if usable(cur) then return cur end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable(win) then return win end
  end
  -- Only panels and the like on screen: a scratch window, which
  -- ensure_normal_buffer() fills with a real buffer right away.
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  return vim.api.nvim_open_win(scratch, true, { split = "left", win = -1 })
end

local function build(force)
  local target
  -- Terminals on screen (Claude sessions among them) come back where they were.
  local term = require("config.term")
  local terminals = term.visible()
  -- Rebuilt by an autocmd (the tree went missing), a running debugger keeps
  -- its panels; <leader>l is the way out and closes them.
  local reopen_debug = not force and package.loaded["config.debug"] and debug_panels_open()

  if force then
    target = file_in_view()
    close_diff_views()
  end
  close_panels()

  vim.api.nvim_set_current_win(main_window())
  ensure_normal_buffer()
  if type(target) == "string" then
    pcall(vim.cmd, "edit " .. vim.fn.fnameescape(target))
  elseif target and vim.api.nvim_buf_is_valid(target) then
    vim.api.nvim_set_current_buf(target)
  end
  vim.cmd("silent only")
  local main_win = vim.api.nvim_get_current_win()
  plain_window(main_win)
  local main_buf = vim.api.nvim_win_get_buf(main_win)

  pcall(function() vim.cmd("NvimTreeOpen") end)
  if reopen_debug then pcall(require("config.debug").open, { focus = false }) end
  for _, buf in ipairs(terminals) do pcall(term.show, buf, { focus = false }) end
  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end
  pcall(welcome.paint, main_buf)
end

-- force = true (:Layout / <leader>l) rebuilds unconditionally: it is the way
-- home from any diff view, the debugger and a leetcode session, with the file
-- you were on open as a plain file. The automatic triggers leave diffs and
-- leetcode alone. Terminals that were on screen (Claude too) stay.
local function setup_layout(force)
  if state.building then return end
  if state.leetcode then
    if not force then return end
    state.leetcode = false
  end

  state.building = true
  local ok, err = xpcall(build, debug.traceback, force)
  -- Always reset: a stuck flag would switch every layout autocmd off for good.
  state.building = false
  if not ok then
    vim.notify("Layout restore failed: " .. err, vim.log.levels.ERROR)
  end
end

-- Diffview (and :diffsplit) builds a tree-less multi-window tabpage; without
-- this check the BufEnter autocmd below would see "layout broken" and its
-- `only` would close the diff windows the moment a file buffer is entered.
local function diff_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    if vim.wo[win].diff
      or ft == "DiffviewFiles" or ft == "DiffviewFileHistory" or ft == "MergeConflicts"
    then
      return true
    end
  end
  return false
end

local function layout_intact()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "NvimTree" then
      return true
    end
  end
  return false
end

local M = {}

--- Back to the startup layout from anywhere, with the file you were on open.
function M.home() setup_layout(true) end

vim.api.nvim_create_user_command("Layout", M.home, {})
vim.keymap.set("n", "<leader>l", M.home, { desc = "Restore startup layout (closes every diff view)" })

vim.api.nvim_create_autocmd("VimEnter", { callback = function() setup_layout() end })

vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    if state.building then return end
    if vim.bo.buftype ~= "" or vim.bo.filetype == "NvimTree" then return end
    if diff_tabpage() then return end
    if layout_intact() then return end
    vim.schedule(setup_layout)
  end,
})

-- Tree left as the last window -> rebuild instead of an all-tree screen.
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    if state.building then return end
    vim.schedule(function()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      if #wins == 1 then
        local buf = vim.api.nvim_win_get_buf(wins[1])
        if vim.bo[buf].filetype == "NvimTree" then
          setup_layout()
        end
      end
    end)
  end,
})

return M
