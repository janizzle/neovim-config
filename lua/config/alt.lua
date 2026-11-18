-- Alt+h/j/k/l, spelled every way a terminal may send them.
--
-- With Option set to "Normal" (iTerm2's default), macOS never sends Alt: the
-- key types whatever the keyboard layout puts on Option+letter, and Neovim
-- just inserts it. On the U.S. layout that is ˙ ∆ ˚ ¬. Mapping those as well
-- makes the Alt maps work either way. Set iTerm2 > Settings > Profiles > Keys
-- > Left Option key to "Esc+" to get real Alt keys (tmux needs that for its
-- own M-hjkl pane switching).

local M = {}

local MAC = { h = "˙", j = "∆", k = "˚", l = "¬" }

M.names = { h = "left", j = "below", k = "above", l = "right" }

--- dir -> list of lhs: { h = { "<A-h>", "˙" }, ... }
M.keys = {}
for dir in pairs(M.names) do
  M.keys[dir] = { "<A-" .. dir .. ">" }
  if vim.fn.has("mac") == 1 then table.insert(M.keys[dir], MAC[dir]) end
end

return M
