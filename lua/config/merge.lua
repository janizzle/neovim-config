-- Merge-conflict workspace, built on diffview.
--
-- `:Merge` (or <leader>dm) opens diffview and stacks a second list on the left
-- edge, so the tabpage reads:
--
--   +--------------------+--------------------------------------------------+
--   | CONFLICTS  (list)  |                                                  |
--   +--------------------+   OURS   |   working file   |   THEIRS           |
--   | changed files      |  (HEAD)  |   (you edit me)  |  (merged-in)       |
--   | (diffview panel)   |                                                  |
--   +--------------------+--------------------------------------------------+
--
-- The three windows are diffview's `diff3_horizontal` merge tool, configured in
-- plugins/diffview.lua. The conflict list is ours: diffview's own panel groups
-- conflicts into a section of the single file panel rather than a window of its
-- own, so we render one here and drive the view through `set_file_by_path`.

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

local ns = api.nvim_create_namespace("MergeConflictsPanel")
local augroup = api.nvim_create_augroup("MergeConflicts", { clear = true })

local panel = { win = nil, buf = nil, root = nil, entries = {} }
local pending = false
local timer

-- Git ------------------------------------------------------------------------

local function git(args)
  local out = vim.fn.systemlist(vim.list_extend({ "git" }, args))
  if vim.v.shell_error ~= 0 then return nil end
  return out
end

local function repo_root()
  local out = git({ "rev-parse", "--show-toplevel" })
  if out and out[1] and out[1] ~= "" then return out[1] end
end

--- Buffer currently holding `abs`, if any -- a file open in the merge tool has
--- unwritten edits, and those are the ones worth counting.
local function buffer_for(abs)
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and api.nvim_buf_get_name(b) == abs then
      return b
    end
  end
end

local function count_conflicts(abs)
  local lines
  local buf = buffer_for(abs)
  if buf then
    -- Once the result view is attached the markers are gone from the buffer, so
    -- counting them would report every file as clean. Ask it instead.
    local pending_blocks = require("config.mergeresult").unresolved(buf)
    if pending_blocks then return pending_blocks end
    lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  else
    local ok, res = pcall(vim.fn.readfile, abs)
    if not ok then return 0 end
    lines = res
  end
  local n = 0
  for _, line in ipairs(lines) do
    if line:sub(1, 7) == "<<<<<<<" then n = n + 1 end
  end
  return n
end

--- Unmerged paths, relative to the repo root (same form as diffview's
--- `FileEntry.path`), each with the number of conflict regions still left.
local function collect()
  local root = repo_root()
  if not root then return nil, {} end
  local entries = {}
  for _, rel in ipairs(git({ "diff", "--name-only", "--diff-filter=U" }) or {}) do
    if rel ~= "" then
      entries[#entries + 1] = { path = rel, count = count_conflicts(root .. "/" .. rel) }
    end
  end
  return root, entries
end

-- Merge-tool panes ------------------------------------------------------------

local labels = { ours = "HEAD", theirs = "MERGE_HEAD" }

local function read_labels()
  local head = git({ "symbolic-ref", "--short", "HEAD" })
  labels.ours = (head and head[1] ~= "" and head[1]) or "HEAD"

  local named = git({ "name-rev", "--name-only", "MERGE_HEAD" })
  local theirs = named and named[1]
  if theirs and theirs ~= "" and theirs ~= "undefined" then
    labels.theirs = (theirs:gsub("^remotes/", ""))
  else
    labels.theirs = "MERGE_HEAD"
  end

  require("config.mergeresult").set_labels(labels)
end

--- The tabpage's diff windows in reading order: top to bottom, then left to
--- right. For diff3_horizontal that is OURS, RESULT, THEIRS; for the *_mixed
--- layouts the two sides sit on the top row and RESULT spans the bottom.
local function diff_windows()
  local wins = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.wo[win].diff then wins[#wins + 1] = win end
  end
  table.sort(wins, function(a, b)
    local pa, pb = api.nvim_win_get_position(a), api.nvim_win_get_position(b)
    if pa[1] ~= pb[1] then return pa[1] < pb[1] end
    return pa[2] < pb[2]
  end)
  return wins
end

--- True when every window starts on the same screen row, i.e. they are side by
--- side rather than stacked.
local function all_in_one_row(wins)
  local row = api.nvim_win_get_position(wins[1])[1]
  for _, win in ipairs(wins) do
    if api.nvim_win_get_position(win)[1] ~= row then return false end
  end
  return true
end

local function winbar(group, text)
  return ("%%#%s# %s %%#MergeWinbarFill#"):format(group, (text:gsub("%%", "%%%%")))
end

--- Label and recolor the panes. Vim's diff highlighting is per window and knows
--- nothing about "ours" and "theirs", so map the generic Diff* groups onto
--- side-specific ones through `winhighlight` -- the same trick diffview uses for
--- its 2-way layout, which it never applies to the 3-way one. Re-applied after
--- every relayout because diffview rebuilds these windows from scratch.
local function style_panes()
  local wins = diff_windows()
  for _, win in ipairs(wins) do
    vim.wo[win].list = false
  end

  local mr = require("config.mergeresult")

  -- A side pane shows what *that side* did, and nothing else. Vim's diff would
  -- light up every line that merely differs from the pane next door -- which
  -- marks THEIRS for a line their branch never touched, just because our side
  -- changed it. So each side is measured against the merge base instead, and
  -- vim's colours are switched off wherever we can do that (see paint_side).
  -- Red never appears in a side pane: it means "conflict" and belongs in the
  -- result pane, where the keys are.
  local ours   = { side = "ours",   bar = "MergeWinbarOurs",   title = "OURS · " .. labels.ours,
                   body = "MergeOursDiff",   text = "MergeOursDiffText" }
  local theirs = { side = "theirs", bar = "MergeWinbarTheirs", title = "THEIRS · " .. labels.theirs,
                   body = "MergeTheirsDiff", text = "MergeTheirsDiffText" }
  local result = { bar = "MergeWinbarResult", title = "RESULT · merged",
                   body = "MergeCenter", text = "MergeCenterText" }

  local order
  if #wins == 1 then
    -- diff1_plain: just the working file. Nothing to line up against, so the
    -- conflict bands are the whole story.
    order = { result }
  elseif #wins == 3 then
    order = all_in_one_row(wins)
      and { ours, result, theirs }   -- diff3_horizontal
      or { ours, theirs, result }    -- diff3_mixed: sides on top, result below
  end

  if order then
    -- Collapse the markers before painting anything: whether that succeeded
    -- decides who owns the colours in all three panes, not just the middle one.
    local merged = false
    for i, win in ipairs(wins) do
      if order[i] == result then merged = mr.attach(api.nvim_win_get_buf(win)) end
    end

    for i, win in ipairs(wins) do
      local spec = order[i]
      local buf = api.nvim_win_get_buf(win)
      local body, text = spec.body, spec.text

      -- Both the result pane and the side panes paint themselves per line when
      -- the result view is up. Vim's diff highlighting only knows "this row
      -- differs from some other pane" -- a second, coarser opinion painted over
      -- ours -- so switch it off rather than let the two fight.
      if merged and spec == result then
        body, text = "MergeResultPlain", "MergeResultPlain"
        -- The block brackets live in the gutter; "auto" would hide them the
        -- moment a file has no other signs.
        vim.wo[win].signcolumn = "yes:1"
      elseif merged and spec.side and mr.paint_side(buf, spec.side) then
        body, text = "MergeResultPlain", "MergeResultPlain"
      end

      vim.wo[win].winhighlight = table.concat({
        "DiffAdd:" .. body,
        "DiffChange:" .. body,
        "DiffText:" .. text,
        "DiffDelete:MergeFiller",
      }, ",")
      vim.wo[win].winbar = winbar(spec.bar, spec.title)
    end

    -- Diffview maps co/ct/cb/c0/cn/cp on every diff buffer to its own
    -- marker-based actions, and re-maps them on every relayout. In a pane whose
    -- markers we have collapsed those can only be silent no-ops, so once the
    -- result view is up, claim the keys back for all three panes -- ours go on
    -- last, and they work the same whichever pane you press them in.
    if mr.result_win() then
      for _, win in ipairs(wins) do mr.attach_keymaps(api.nvim_win_get_buf(win)) end
    end
  elseif #wins == 2 then
    -- A plain changed file: no sides to tell apart, so leave the normal diff
    -- colours alone and only quiet down the filler.
    local titles = { "HEAD · " .. labels.ours, "WORKING TREE" }
    for i, win in ipairs(wins) do
      vim.wo[win].winhighlight = "DiffDelete:MergeFiller"
      vim.wo[win].winbar = winbar("MergeWinbarSide", titles[i])
    end
  end
end

-- Panel ----------------------------------------------------------------------

local function entry_at_cursor()
  if not (panel.win and api.nvim_win_is_valid(panel.win)) then return end
  local row = api.nvim_win_get_cursor(panel.win)[1]
  return panel.entries[row - 1]  -- line 1 is the header
end

local function current_view()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok then return end
  local view = lib.get_current_view()
  if view and view.set_file_by_path then return view end
end

local function open_entry()
  local entry = entry_at_cursor()
  local view = current_view()
  if not (entry and view) then return end
  -- focus = true lands the cursor in the middle (working file) window, which is
  -- the one you actually resolve in; highlight = true syncs diffview's panel.
  view:set_file_by_path(entry.path, true, true)
end

local function render()
  if not (panel.buf and api.nvim_buf_is_valid(panel.buf)) then return end

  local root, entries = collect()
  panel.root, panel.entries = root, entries

  local regions = 0
  for _, e in ipairs(entries) do regions = regions + e.count end

  local lines, marks = {}, {}

  if #entries == 0 then
    lines[1] = "  CONFLICTS  none"
    lines[2] = "  nothing to merge"
    marks[#marks + 1] = { 1, 0, -1, "MergeConflictsEmpty" }
  else
    lines[1] = ("  CONFLICTS  %d file%s · %d region%s"):format(
      #entries, #entries == 1 and "" or "s",
      regions, regions == 1 and "" or "s")
  end
  marks[#marks + 1] = { 0, 0, -1, "MergeConflictsTitle" }

  for i, e in ipairs(entries) do
    local icon  = e.count > 0 and "●" or "✓"
    local count = e.count > 0 and tostring(e.count) or "-"
    local prefix = "  " .. icon .. " " .. count .. string.rep(" ", math.max(1, 4 - #count))
    lines[i + 1] = prefix .. e.path

    local row = i
    marks[#marks + 1] = {
      row, 2, 2 + #icon + 1 + #count,
      e.count > 0 and "MergeConflictsCount" or "MergeConflictsDone",
    }
    local dir = e.path:match("^(.*/)")
    local name_col = #prefix + (dir and #dir or 0)
    if dir then
      marks[#marks + 1] = { row, #prefix, name_col, "MergeConflictsDir" }
    end
    marks[#marks + 1] = { row, name_col, -1, "MergeConflictsPath" }
  end

  vim.bo[panel.buf].modifiable = true
  api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false

  api.nvim_buf_clear_namespace(panel.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local row, col, end_col, group = m[1], m[2], m[3], m[4]
    if end_col < 0 then end_col = #lines[row + 1] end
    pcall(api.nvim_buf_set_extmark, panel.buf, ns, row, col, {
      end_col = math.min(end_col, #lines[row + 1]),
      hl_group = group,
    })
  end

  -- Keep the cursor on a real row after files drop out of the list.
  if panel.win and api.nvim_win_is_valid(panel.win) then
    local row = api.nvim_win_get_cursor(panel.win)[1]
    if row > #lines then
      api.nvim_win_set_cursor(panel.win, { math.max(1, #lines), 0 })
    end
  end
end

local function resize()
  if not (panel.win and api.nvim_win_is_valid(panel.win)) then return end
  api.nvim_win_set_height(panel.win, math.max(3, math.min(#panel.entries + 1, 12)))
end

local function schedule_render()
  if not (panel.win and api.nvim_win_is_valid(panel.win)) then return end
  timer = timer or uv.new_timer()
  timer:stop()
  timer:start(120, 0, vim.schedule_wrap(function()
    render()
    resize()
  end))
end

--- Close the conflict list without taking the last window (and so Neovim) down
--- with it.
function M.close_panel()
  local win = panel.win
  panel.win = nil
  if not (win and api.nvim_win_is_valid(win)) then return end
  local tab = api.nvim_win_get_tabpage(win)
  if #api.nvim_tabpage_list_wins(tab) == 1 and #api.nvim_list_tabpages() == 1 then
    api.nvim_win_call(win, function() vim.cmd("enew") end)
    return
  end
  pcall(api.nvim_win_close, win, true)
end

function M.close()
  M.close_panel()
  pcall(vim.cmd, "DiffviewClose")
end

function M.refresh()
  render()
  resize()
end

local function create_buf()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "MergeConflicts"

  local name = "diffview:///panels/merge-conflicts"
  if not pcall(api.nvim_buf_set_name, buf, name) then
    -- A buffer from a previous session still owns the name.
    for _, b in ipairs(api.nvim_list_bufs()) do
      if b ~= buf and api.nvim_buf_get_name(b) == name then
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
    pcall(api.nvim_buf_set_name, buf, name)
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<cr>", open_entry, "Open this conflict in the merge tool")
  map("o", open_entry, "Open this conflict in the merge tool")
  map("<2-LeftMouse>", open_entry, "Open this conflict in the merge tool")
  map("r", M.refresh, "Refresh the conflict list")
  map("q", M.close, "Close the merge view")

  return buf
end

local function open_panel(view)
  if panel.win and api.nvim_win_is_valid(panel.win) then return end

  local host = view.panel and view.panel.winid
  if not (host and api.nvim_win_is_valid(host)) then return end

  if not (panel.buf and api.nvim_buf_is_valid(panel.buf)) then
    panel.buf = create_buf()
  end

  -- Split the file panel's own column: our list on top, diffview's changed-file
  -- panel below. nvim_win_call restores the previously focused window for us.
  api.nvim_win_call(host, function()
    vim.cmd("aboveleft split")
    panel.win = api.nvim_get_current_win()
    api.nvim_win_set_buf(panel.win, panel.buf)
  end)

  local w = panel.win
  vim.wo[w].number = false
  vim.wo[w].relativenumber = false
  vim.wo[w].list = false
  vim.wo[w].wrap = false
  vim.wo[w].spell = false
  vim.wo[w].cursorline = true
  vim.wo[w].signcolumn = "no"
  vim.wo[w].foldcolumn = "0"
  vim.wo[w].colorcolumn = ""
  vim.wo[w].winfixheight = true
  vim.wo[w].winfixwidth = true
  vim.wo[w].winhighlight =
    "Normal:MergeConflictsNormal,CursorLine:MergeConflictsCursorLine,EndOfBuffer:MergeConflictsNormal"
end

--- True when our list is no longer sitting directly on top of diffview's file
--- panel. Switching between a conflicting file (3 windows) and a plain changed
--- file (2 windows) makes diffview rebuild the layout, and the rebuild closes
--- and re-opens its file panel with `wincmd H` -- which shoves any window that
--- shared its column off to the side. Cheaper to detect and re-split than to
--- fight it.
local function panel_misplaced(view)
  local host = view.panel and view.panel.winid
  if not (host and api.nvim_win_is_valid(host)) then return false end
  if not (panel.win and api.nvim_win_is_valid(panel.win)) then return true end
  if api.nvim_win_get_tabpage(panel.win) ~= api.nvim_win_get_tabpage(host) then
    return true
  end
  local mine, theirs = api.nvim_win_get_position(panel.win), api.nvim_win_get_position(host)
  return not (mine[2] == theirs[2]                                     -- same column
    and api.nvim_win_get_width(panel.win) == api.nvim_win_get_width(host)
    and mine[1] < theirs[1])                                           -- and above it
end

--- Put the list back on top of the file panel if a relayout displaced it, then
--- redraw. Safe to call on every diffview event.
local function reanchor()
  local view = current_view()
  if not view then return end
  if panel_misplaced(view) then
    M.close_panel()
    open_panel(view)
  end
  style_panes()
  render()
  resize()
end

--- Attach the conflict list to the diffview in the current tabpage. Diffview
--- builds its file panel asynchronously, so retry briefly until it exists.
local function attach(tries)
  tries = tries or 0
  local view = current_view()
  if not (view and view.panel and view.panel.winid
    and api.nvim_win_is_valid(view.panel.winid)) then
    if tries < 40 then
      vim.defer_fn(function() attach(tries + 1) end, 50)
    end
    return
  end

  render()

  -- Select the first unresolved file before splitting off our window: opening a
  -- conflict swaps diffview into the 3-window merge layout, and that rebuild
  -- would displace the list if it already existed.
  local first = panel.entries[1]
  if first then view:set_file_by_path(first.path, false, true) end

  vim.defer_fn(function()
    reanchor()
    if first and panel.win and api.nvim_win_is_valid(panel.win) then
      pcall(api.nvim_win_set_cursor, panel.win, { 2, 0 })
    end
  end, first and 200 or 0)
end

-- Entry point ------------------------------------------------------------------

function M.open()
  if not repo_root() then
    vim.notify("Merge: not inside a git repository", vim.log.levels.ERROR)
    return
  end

  local _, entries = collect()
  if #entries == 0 then
    vim.notify("Merge: no conflicting files -- showing working-tree changes", vim.log.levels.INFO)
  end

  read_labels()
  pending = true
  vim.cmd("DiffviewOpen")
  -- DiffviewOpen reuses an already-open view without re-firing
  -- DiffviewViewOpened; attach anyway if the event never came.
  vim.defer_fn(function()
    if pending then
      pending = false
      attach()
    end
  end, 400)
end

api.nvim_create_user_command("Merge", M.open, { desc = "Merge conflicts: diffview + conflict list" })

api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "DiffviewViewOpened",
  callback = function()
    if not pending then return end
    pending = false
    vim.schedule(attach)
  end,
})

api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "DiffviewViewClosed",
  callback = function() M.close_panel() end,
})

-- Any of these can follow a layout rebuild, so re-anchor rather than just
-- redraw. Skipped entirely once the list has been closed.
api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = { "DiffviewViewEnter", "DiffviewDiffBufWinEnter", "DiffviewViewPostLayout" },
  callback = function()
    if not (panel.win and api.nvim_win_is_valid(panel.win)) then return end
    vim.schedule(reanchor)
  end,
})

-- Resolving a conflict edits the working file in place; recount as it happens
-- rather than only on write.
api.nvim_create_autocmd({ "BufWritePost", "TextChanged", "InsertLeave" }, {
  group = augroup,
  callback = schedule_render,
})

return M
