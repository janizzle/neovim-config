-- Resizing moves the nearest border in the direction pressed, like tmux:
-- right always pushes a border right, whichever side of it this view is on.
-- (Plain <C-w>> means "this view wider", which in the rightmost view drags
-- its left border left -- backwards on an arrow key.)

local api = vim.api

local M = {}

--- Move the border next to `win` (default: current) one step towards `dir`.
--- A panel across that border with a fixed size (file tree, a Claude column) is
--- resized itself: growing this view would otherwise take the room from the
--- view on the far side and move the wrong border.
function M.nudge(dir, step, win)
  api.nvim_win_call(win or 0, function()
    local vertical = dir == "h" or dir == "l"
    local forward = dir == "l" or dir == "j"
    local has_after = vim.fn.winnr(vertical and "l" or "j") ~= vim.fn.winnr()
    local delta = forward == has_after and step or -step

    local across = vim.fn.win_getid(vim.fn.winnr(vertical and (has_after and "l" or "h") or (has_after and "j" or "k")))
    local target = 0
    if across ~= 0 and across ~= api.nvim_get_current_win()
      and vim.wo[across][vertical and "winfixwidth" or "winfixheight"]
    then
      target, delta = across, -delta
    end

    if vertical then
      api.nvim_win_set_width(target, math.max(1, api.nvim_win_get_width(target) + delta))
    else
      api.nvim_win_set_height(target, math.max(1, api.nvim_win_get_height(target) + delta))
    end
  end)
end

M.ARROW_DIRS = { ["<Left>"] = "h", ["<Down>"] = "j", ["<Up>"] = "k", ["<Right>"] = "l" }

--- <C-w> + arrow resizes, then stays in resize mode (shown in the command
--- line): more arrows, with or without another <C-w> in front, keep going.
--- <Esc> leaves; any other key leaves and then does its normal thing.
--- A count multiplies the first step (5<C-w><Right>).
--- `win` resizes that window instead of the current one.
function M.loop(key, win)
  local step = vim.v.count1 * 2
  while M.ARROW_DIRS[key] do
    M.nudge(M.ARROW_DIRS[key], step, win)
    step = 2
    api.nvim_echo({ { "-- RESIZE --", "ModeMsg" }, { "  arrows move the border, <Esc> stops" } }, false, {})
    vim.cmd.redraw()
    local ok, raw = pcall(vim.fn.getcharstr)
    if not ok then break end  -- <C-c>
    key = vim.fn.keytrans(raw)
    if key == "<C-W>" then
      local ok2, nxt = pcall(vim.fn.getcharstr)
      if not ok2 then break end
      raw, key = raw .. nxt, vim.fn.keytrans(nxt)
    end
    if not M.ARROW_DIRS[key] and key ~= "<Esc>" then
      api.nvim_feedkeys(raw, "mi", false)  -- "i": ahead of keys already queued
    end
  end
  api.nvim_echo({ { "" } }, false, {})
end

return M
