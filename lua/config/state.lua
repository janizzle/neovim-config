-- Shared mutable flags.
-- `building`: layout autocmds stand down while windows are deliberately being
-- rearranged (setup_layout itself, telescope's reveal_dir).
-- `leetcode`: leetcode.nvim owns the screen; the startup layout must not tear
-- down its multi-window layout.

local M = {}

M.building = false
M.leetcode = false

return M
