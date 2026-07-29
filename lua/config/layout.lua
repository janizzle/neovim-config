-- Startup layout: open the file tree on the left, paint the welcome screen in
-- the main window, and keep that layout intact (reopen the tree if it's the
-- last window, restore on demand with <leader>l / :Layout).

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

local function setup_layout()
  if state.building then return end
  state.building = true
  ensure_normal_buffer()
  vim.cmd("only")
  local main_win = vim.api.nvim_get_current_win()
  local main_buf = vim.api.nvim_win_get_buf(main_win)

  pcall(function() vim.cmd("NvimTreeOpen") end)
  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end

  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end
  pcall(welcome.paint, main_buf)
  state.building = false
end

local function layout_intact()
  local has_tree = false
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "NvimTree" then has_tree = true end
  end
  return has_tree
end

vim.api.nvim_create_user_command("Layout", setup_layout, {})
vim.keymap.set("n", "<leader>l", setup_layout, { desc = "Restore startup layout" })

vim.api.nvim_create_autocmd("VimEnter", { callback = setup_layout })

vim.api.nvim_create_autocmd("BufEnter", {
  callback = function()
    if state.building then return end
    if vim.bo.buftype ~= "" or vim.bo.filetype == "NvimTree" then return end
    if layout_intact() then return end
    vim.schedule(setup_layout)
  end,
})

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.bo.buflisted = false
    vim.wo.colorcolumn = ""   -- no line-length rule in terminals
  end,
})

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
