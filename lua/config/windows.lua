-- Window helpers shared between the telescope actions and the layout code.

local M = {}

--- First window in the tabpage that is neither the file tree, the blame
--- column nor a terminal -- where opened files should land.
--- @return integer|nil window handle
function M.find_main_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= "NvimTree"
      and vim.bo[buf].filetype ~= "blame"
      and vim.bo[buf].buftype ~= "terminal"
    then
      return win
    end
  end
end

return M
