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

-- force = true (:Layout / <leader>l) rebuilds unconditionally and is the way
-- out of a leetcode session; the automatic triggers leave leetcode alone.
local function setup_layout(force)
  if state.building then return end
  if state.leetcode then
    if not force then return end
    state.leetcode = false
  end
  state.building = true
  ensure_normal_buffer()
  vim.cmd("only")
  local main_win = vim.api.nvim_get_current_win()
  local main_buf = vim.api.nvim_win_get_buf(main_win)

  pcall(function() vim.cmd("NvimTreeOpen") end)
  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end
  pcall(welcome.paint, main_buf)
  state.building = false
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

vim.api.nvim_create_user_command("Layout", function() setup_layout(true) end, {})
vim.keymap.set("n", "<leader>l", function() setup_layout(true) end, { desc = "Restore startup layout" })

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

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.bo.buflisted = false
    vim.wo.colorcolumn = ""
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
