-- Small orange floats stacked in the top-right corner. vim.notify's default is
-- a one-line echo that is gone by the next redraw.

local M = {}

local ICON = vim.fn.nr2char(0xF06A9) -- nf-md-robot
M.ICON = ICON

local toasts = {}
local ns = vim.api.nvim_create_namespace("ClaudeToast")

local function layout()
  local row = 1
  for _, t in ipairs(toasts) do
    if vim.api.nvim_win_is_valid(t.win) then
      vim.api.nvim_win_set_config(t.win, {
        relative = "editor", row = row, col = math.max(vim.o.columns - t.width - 3, 0),
      })
      row = row + 3
    end
  end
end
M.layout = layout

--- chunks = { {text, hl?}, ... }; hl defaults to the toast colour.
function M.show(chunks, ms)
  local line, marks = " " .. ICON .. "  ", {}
  for _, c in ipairs(chunks) do
    if c[2] then marks[#marks + 1] = { #line, #line + #c[1], c[2] } end
    line = line .. c[1]
  end
  line = line .. " "

  local width = vim.fn.strdisplaywidth(line)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, 0, m[1], { end_col = m[2], hl_group = m[3] })
  end
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 1, col = math.max(vim.o.columns - width - 3, 0),
    width = width, height = 1, style = "minimal", border = "rounded",
    focusable = false, zindex = 250, noautocmd = true,
  })
  vim.wo[win].winhighlight = "NormalFloat:ClaudeToast,FloatBorder:ClaudeToastBorder"

  local t = { win = win, width = width }
  table.insert(toasts, t)
  layout()
  vim.defer_fn(function()
    for i, x in ipairs(toasts) do if x == t then table.remove(toasts, i) break end end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    layout()
  end, ms or 6000)
end

return M
