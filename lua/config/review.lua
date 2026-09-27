-- Review workspace: every change since the last commit, one file at a time.
--
-- `:Review` (or <leader>dd) opens diffview against HEAD with the panes turned
-- round, so the tabpage reads like the merge workspace:
--
--   +--------------------+--------------------------------------------------+
--   | changed files      |   WORKING TREE           |   HEAD                |
--   | (tree)             |   your file, edit me     |   as last committed   |
--   +--------------------+--------------------------------------------------+
--
-- Diffview puts the old text on the left and has no option to flip it. Its
-- layouts track their windows by id, not by position, so once the two panes
-- are built we just swap where they sit; a relayout rebuilds them in the stock
-- order and the next event swaps them back. Only views opened from here are
-- touched -- <leader>dv and friends keep diffview's own order.

local api = vim.api

local M = {}

local augroup = api.nvim_create_augroup("ReviewChanges", { clear = true })

-- Views opened by M.open(); weak keys so a closed view doesn't linger.
local ours = setmetatable({}, { __mode = "k" })
local pending = false

local function current_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then return end
  return lib.get_current_view()
end

local function winbar(group, text)
  return ("%%#%s# %s %%#DiffSideWinbarFill#"):format(group, (text:gsub("%%", "%%%%")))
end

--- Working tree on the left, HEAD on the right, labelled the same way as
--- <leader>ds. Safe to call on every diffview event: it only swaps when the
--- panes are in diffview's order.
local function arrange()
  local view = current_view()
  if not (view and ours[view]) then return end
  local layout = view.cur_layout
  -- Two-pane layouts only; a deleted or brand-new file may show just one.
  if not (layout and layout.a and layout.b) then return end
  local old, new = layout.a.id, layout.b.id
  if not (old and new and api.nvim_win_is_valid(old) and api.nvim_win_is_valid(new)) then return end

  if api.nvim_win_get_position(old)[2] < api.nvim_win_get_position(new)[2] then
    local cur = api.nvim_get_current_win()
    -- <C-w>x trades places with the next window in the row, which is `new`.
    api.nvim_win_call(old, function() vim.cmd("wincmd x") end)
    if api.nvim_win_is_valid(cur) then api.nvim_set_current_win(cur) end
  end

  for _, win in ipairs({ old, new }) do
    vim.wo[win].list = false
    -- Whole files, not hunks, like the other diff views. Diffview re-applies
    -- its folds on every relayout, which re-runs this.
    vim.wo[win].foldenable = false
  end

  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(api.nvim_win_get_buf(new)), ":t")
  vim.wo[new].winbar = winbar("DiffSideWinbarNew", "WORKING TREE · " .. name)
  vim.wo[old].winbar = winbar("DiffSideWinbarOld", "HEAD · as committed")
end

function M.open()
  pending = true
  -- Against HEAD rather than the index: staged and unstaged edits land in one
  -- list, and the right pane is always the file as last committed.
  vim.cmd("DiffviewOpen HEAD")
end

api.nvim_create_user_command("Review", M.open,
  { desc = "Review changes: tree + working tree | HEAD" })

api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "DiffviewViewOpened",
  callback = function()
    if not pending then return end
    pending = false
    local view = current_view()
    if view then ours[view] = true end
    vim.schedule(arrange)
  end,
})

api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = { "DiffviewViewEnter", "DiffviewDiffBufWinEnter", "DiffviewViewPostLayout" },
  callback = function() vim.schedule(arrange) end,
})

return M
