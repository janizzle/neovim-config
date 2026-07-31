-- Shared mutable flags used across otherwise-independent modules.
-- `building` guards the layout autocmds while we (or a plugin action such as
-- telescope's reveal_dir) are deliberately rearranging windows, so those
-- rearrangements don't retrigger setup_layout() mid-flight.

-- `leetcode` is set while leetcode.nvim owns the screen: it builds its own
-- multi-window layout (question / description / console), which the startup
-- layout would otherwise tear down with `only` on the next BufEnter.

local M = {}

M.building = false
M.leetcode = false

return M
