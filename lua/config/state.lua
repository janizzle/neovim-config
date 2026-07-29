-- Shared mutable flags used across otherwise-independent modules.
-- `building` guards the layout autocmds while we (or a plugin action such as
-- telescope's reveal_dir) are deliberately rearranging windows, so those
-- rearrangements don't retrigger setup_layout() mid-flight.

local M = {}

M.building = false

return M
