-- IntelliJ-style merge *result* buffer.
--
-- Git leaves a conflicted file with ours and theirs stacked one after the other
-- between <<<<<<< / ======= / >>>>>>> markers. That is the whole reason
-- diffview's middle pane can never line up with both side panes at once: the
-- same block lives at two different heights in the middle buffer, and the three
-- windows are scroll-locked by screen row.
--
-- This module rewrites that buffer into a result: every conflict collapses to a
-- single block (initialised to OURS), the markers disappear, and all three
-- buffers then diff row-for-row -- which is exactly what IntelliJ's merge
-- dialog shows you.
--
-- Each collapsed block is tracked by an extmark, so it follows your own edits,
-- and ct/co/cb/c0 swap the block's contents in place. Nothing reaches disk
-- until you `:w`; `:MergeMarkers` puts the original marker text back.
--
-- The pane is also painted here rather than by vim's diff engine, which only
-- ever knows "this row differs from the pane next door" -- the same answer for
-- a hunk git merged and a hunk still waiting on you. Two layers:
--
--   band (per block)  red    still a conflict; ct/co/cb/c0 act on this block,
--                            and it is bracketed in the gutter so you can see
--                            exactly what one keypress replaces
--   tint (per line)   blue   this line came from our side
--                     purple this line came from their side
--                     grey   matches neither side: you typed it
--
-- Only open conflicts get a band. Answer one and the band goes -- the lines
-- keep the tint of whichever side you gave them, which is the same tint the
-- hunks git merged for you already carry. So what is marked red is always and
-- only what is still left to do.

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace("MergeResult")
local sign_ns = api.nvim_create_namespace("MergeResultSigns")
local origin_ns = api.nvim_create_namespace("MergeResultOrigin")

--- bufnr -> { original = string[], regions = region[], ours = string[]?, theirs = string[]? }
--- region = { id, row, len, ours, base, theirs, choice, resolved }
local state = {}

M.namespace = ns
M.sign_namespace = sign_ns
M.origin_namespace = origin_ns

-- Parsing ---------------------------------------------------------------------

local function is_marker(line, marker)
  return line:sub(1, 7) == marker
end

--- Split marker'd content into plain lines plus the conflict regions.
--- Returns nil when there is nothing to do (no conflicts) or when the markers
--- are malformed -- in that case the buffer is left exactly as it was.
--- @return string[]? lines, table[]? regions
local function parse(lines)
  local out, regions = {}, {}
  local i, n = 1, #lines

  while i <= n do
    if is_marker(lines[i], "<<<<<<<") then
      local ours, base, theirs = {}, nil, {}
      local target, closed = ours, false
      i = i + 1

      while i <= n do
        local line = lines[i]
        if is_marker(line, "|||||||") then       -- only with conflictstyle=diff3
          base = {}
          target = base
        elseif is_marker(line, "=======") then
          target = theirs
        elseif is_marker(line, ">>>>>>>") then
          closed = true
          i = i + 1
          break
        else
          target[#target + 1] = line
        end
        i = i + 1
      end

      if not closed then return nil end

      regions[#regions + 1] = {
        row = #out,          -- 0-indexed start row in the result
        ours = ours,
        base = base,
        theirs = theirs,
        choice = "ours",
        resolved = false,
      }
      vim.list_extend(out, ours)
    else
      out[#out + 1] = lines[i]
      i = i + 1
    end
  end

  if #regions == 0 then return nil end
  return out, regions
end

local function has_markers(buf)
  for _, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if is_marker(line, "<<<<<<<") then return true end
  end
  return false
end

-- Marks -----------------------------------------------------------------------

-- Branch names for the tags, filled in by config/merge.lua so a block can say
-- "THEIRS · feature" rather than just "theirs".
local labels = { ours = "HEAD", theirs = "MERGE_HEAD" }

function M.set_labels(new)
  labels.ours = new.ours or labels.ours
  labels.theirs = new.theirs or labels.theirs
end

--- An undecided block: red, and red means only this. A block you have decided
--- is not marked at all -- it stops being a conflict the moment you answer it,
--- and it keeps only the per-line tint of the side it came from, exactly like
--- the hunks git merged for you. What is still marked is what is still left.
local CONFLICT = { hl = "MergeConflict", tag = "MergeConflictTag", sign = "MergeSignConflict" }

-- The band sits above the per-line origin tints (priority 100) so a conflict is
-- never striped by the colours of the sides it is made of.
local BAND_PRIORITY = 1000

local function mark_opts(buf, region)
  local opts = {
    end_row = region.row + region.len,
    end_col = 0,
    right_gravity = false,
    end_right_gravity = true,
    priority = BAND_PRIORITY,
  }

  -- `end_row` is inclusive and must be a real line, so a block that runs to the
  -- end of the file can't be expressed as "start of the row after it". Pin it to
  -- the last line's end instead; `range()` reads end_col to tell the two forms
  -- apart. Getting this wrong leaves the block's final line behind when it is
  -- replaced, which is silent corruption.
  local last = api.nvim_buf_line_count(buf) - 1
  if opts.end_row > last then
    opts.end_row = last
    opts.end_col = #(api.nvim_buf_get_lines(buf, last, last + 1, false)[1] or "")
  end

  if region.resolved then
    -- Nothing to show: the extmark stays only so the block keeps following
    -- your edits and co/ct can still change your mind about it.
    opts.priority = 1
  else
    -- Undecided blocks hold OURS until you say otherwise -- say so, rather than
    -- letting a block of our code sit there looking like a merge decision. The
    -- band is solid across every line of the block: that rectangle is the unit
    -- ct/co/cb/c0 act on, and it has to be readable as one thing.
    opts.hl_group = CONFLICT.hl
    opts.hl_eol = true
    opts.priority = BAND_PRIORITY
    opts.virt_text = {
      { "  ◆ CONFLICT · showing OURS · " .. labels.ours, CONFLICT.tag },
      { "  ct theirs · co ours · cb both · c0 drop", "MergeHintTag" },
    }
  end
  -- Never virt_lines: an extra screen line here would push this pane out of
  -- step with the other two, which is the exact problem we are removing.
  opts.virt_text_pos = "eol"

  return opts
end

local function place(buf, region)
  region.id = api.nvim_buf_set_extmark(buf, ns, region.row, 0, mark_opts(buf, region))
end

--- Current line range of a region as a half-open [start, end) row pair, read
--- back from its extmark so it survives edits made anywhere above it.
local function range(buf, region)
  local pos = api.nvim_buf_get_extmark_by_id(buf, ns, region.id, { details = true })
  if not pos or not pos[1] then return nil end

  local s = pos[1]
  local details = pos[3] or {}
  local e = details.end_row or s
  -- end_col > 0 means the mark was pinned inside its last line (see mark_opts),
  -- so that line belongs to the block.
  if (details.end_col or 0) > 0 then e = e + 1 end

  return s, math.max(e, s)
end

--- A bracket down the sign column beside every line of every block still
--- waiting on a decision.
---
--- The red band alone can't carry this: two conflicts that happen to touch
--- would read as one region. The corner pieces close each block off, so what
--- you see bracketed is exactly what one keypress replaces.
local BAR = { top = "┌", mid = "│", bottom = "└", only = "◆" }

local function render_signs(buf, st)
  api.nvim_buf_clear_namespace(buf, sign_ns, 0, -1)
  local last = api.nvim_buf_line_count(buf)

  for _, region in ipairs(st.regions) do
    local s, e = range(buf, region)
    -- Decided blocks are left unmarked: the gutter is a list of what is left
    -- to do, and a resolved block is not on it.
    if s and not region.resolved then
      e = math.min(e, last)

      local function bar(row, text)
        pcall(api.nvim_buf_set_extmark, buf, sign_ns, row, 0, {
          sign_text = text,
          sign_hl_group = CONFLICT.sign,
          priority = 200,
        })
      end

      if e - s == 1 then
        bar(s, BAR.only)
      elseif e > s then
        bar(s, BAR.top)
        for row = s + 1, e - 2 do bar(row, BAR.mid) end
        bar(e - 1, BAR.bottom)
      end
    end
  end
end

-- Origin tints -----------------------------------------------------------------

--- Read stages 2 (ours) and 3 (theirs) of the conflicted file straight out of
--- the index. Comparing against those is the only way to say where a line in
--- the result came from: vim's diff engine only knows "this row differs from
--- the pane next door", which is the same answer for a hunk git merged and a
--- hunk you are still arguing with.
local function read_stages(buf)
  local abs = api.nvim_buf_get_name(buf)
  if abs == "" then return end

  local function git(args)
    local out = vim.fn.systemlist(vim.list_extend({ "git" }, args))
    if vim.v.shell_error ~= 0 then return nil end
    return out
  end

  -- --show-prefix rather than trimming the repo root off the absolute path:
  -- the two disagree the moment anything in the path is a symlink, and the
  -- symptom of that is silently losing every tint in the pane.
  local dir = vim.fn.fnamemodify(abs, ":h")
  local prefix = git({ "-C", dir, "rev-parse", "--show-prefix" })
  if not prefix then return end

  local rel = (prefix[1] or "") .. vim.fn.fnamemodify(abs, ":t")
  return git({ "-C", dir, "show", ":2:" .. rel }),
         git({ "-C", dir, "show", ":3:" .. rel }),
         -- Stage 1, the merge base. Absent for an add/add conflict, where the
         -- file has no common ancestor and nothing can be "changed relative to"
         -- anything.
         git({ "-C", dir, "show", ":1:" .. rel })
end

--- Rows of `b` (0-indexed) that differ from `a`.
local function changed_rows(a, b)
  local function text(lines) return table.concat(lines, "\n") .. "\n" end
  local ok, hunks = pcall(vim.diff, text(a), text(b),
    { result_type = "indices", algorithm = "histogram" })
  if not ok or type(hunks) ~= "table" then return nil end

  local rows = {}
  for _, h in ipairs(hunks) do
    local start_b, count_b = h[3], h[4]
    for i = 0, count_b - 1 do rows[start_b - 1 + i] = true end
  end
  return rows
end

--- Tint every line by the side it came from. Lines identical in both stages --
--- the bulk of any file -- stay plain, so what is left coloured is exactly the
--- set of decisions this merge made: blue where ours won, purple where theirs
--- did, grey where neither matches because you typed it yourself.
local function render_origins(buf, st)
  api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
  if not (st.ours and st.theirs) then return end

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local vs_ours = changed_rows(st.ours, lines)
  local vs_theirs = changed_rows(st.theirs, lines)
  if not (vs_ours and vs_theirs) then return end

  for row = 0, #lines - 1 do
    local group
    if vs_ours[row] and vs_theirs[row] then
      group = "MergeAutoLocal"
    elseif vs_ours[row] then
      group = "MergeAutoTheirs"
    elseif vs_theirs[row] then
      group = "MergeAutoOurs"
    end
    if group then
      pcall(api.nvim_buf_set_extmark, buf, origin_ns, row, 0, {
        end_row = row + 1,
        end_col = 0,
        hl_group = group,
        hl_eol = true,
        priority = 100,
      })
    end
  end
end

--- Paint one of the side panes: only the lines that side actually changed,
--- measured against the merge base.
---
--- Vim's diff can't answer this. It compares the panes to each other, so a line
--- only our side touched is marked in *both* panes -- ours for changing it,
--- theirs for the crime of still holding what was always there. Against the
--- base, each side is credited with its own work and nothing else.
---
--- @param side "ours"|"theirs"
--- @return boolean painted -- false when there is no base to measure against
---   (an add/add conflict), so the caller can leave vim's diff colours up.
function M.paint_side(buf, side)
  if not (buf and api.nvim_buf_is_valid(buf)) then return false end

  local win = M.result_win()
  local st = win and state[api.nvim_win_get_buf(win)]
  if not (st and st.base) then return false end

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = changed_rows(st.base, lines)
  if not changed then return false end

  api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
  local group = side == "theirs" and "MergeAutoTheirs" or "MergeAutoOurs"
  for row in pairs(changed) do
    pcall(api.nvim_buf_set_extmark, buf, origin_ns, row, 0, {
      end_row = row + 1,
      end_col = 0,
      hl_group = group,
      hl_eol = true,
      priority = 100,
    })
  end
  return true
end

--- Repaint both layers. Cheap enough to run on every edit: two diffs against
--- strings we already hold, no git call.
local function repaint(buf)
  local st = state[buf]
  if not st then return end
  render_signs(buf, st)
  render_origins(buf, st)
end

M.repaint = repaint

--- gitsigns draws its own bars in this gutter, against the index. Here that is
--- a second thing competing for the one channel that is supposed to mean
--- "conflict block, keys work here" and nothing else. It re-attaches on buffer
--- events, so this gets called on every attach and on every BufEnter rather
--- than once. gitsigns comes back on :MergeMarkers or the next fresh open.
local function silence_gitsigns(buf)
  -- The flag is what actually holds: gitsigns attaches asynchronously, so a
  -- detach issued here can run before it ever attached. plugins/gitsigns.lua
  -- reads this in its on_attach and refuses the buffer.
  vim.b[buf].merge_result = true
  pcall(function() require("gitsigns").detach(buf) end)
end

-- Keymaps ---------------------------------------------------------------------

--- The window in this tabpage that holds the result, if any.
function M.result_win()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if state[api.nvim_win_get_buf(win)] then return win end
  end
end

--- Run `fn` where the blocks actually are.
---
--- Pressing co/ct in the OURS or THEIRS pane is the natural thing to do -- that
--- is the version you are looking at when you decide -- but the blocks only
--- exist in the result buffer, and diffview's own co/ct on those panes work off
--- conflict markers that this module has already removed, so they are silent
--- no-ops. The three panes are cursor-bound, so "the block at the cursor" means
--- the same thing in all of them: run the choice over in the result pane.
local function in_result(fn)
  if state[api.nvim_get_current_buf()] then return fn() end

  local win = M.result_win()
  if not win then
    vim.notify("Merge: no merge result pane in this tab", vim.log.levels.WARN)
    return false
  end
  return api.nvim_win_call(win, fn)
end

function M.attach_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("ct", function() M.choose("theirs") end, "Merge: take THEIRS for this block")
  map("co", function() M.choose("ours") end,   "Merge: take OURS for this block")
  map("cb", function() M.choose("both") end,   "Merge: take BOTH")
  map("c0", function() M.choose("none") end,   "Merge: drop this block")
  map("cB", function() M.choose("base") end,   "Merge: take the BASE version")
  map("cn", function() M.jump(1) end,          "Merge: next unresolved block")
  map("cp", function() M.jump(-1) end,         "Merge: previous unresolved block")
end

-- Public ----------------------------------------------------------------------

--- @param buf integer
--- @return boolean attached
function M.attach(buf)
  if not (buf and api.nvim_buf_is_valid(buf)) then return false end
  if vim.bo[buf].buftype ~= "" then return false end

  if state[buf] then
    -- Still ours unless something reloaded the file from disk under us.
    if not has_markers(buf) then
      silence_gitsigns(buf)
      repaint(buf)
      return true
    end
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, sign_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
    state[buf] = nil
  end

  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local result, regions = parse(lines)
  if not result then return false end

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, result)
  vim.bo[buf].modifiable = was_modifiable

  local ours, theirs, base = read_stages(buf)
  state[buf] = { original = lines, regions = regions, ours = ours, theirs = theirs, base = base }
  for _, region in ipairs(regions) do
    region.len = #region.ours
    place(buf, region)
  end
  repaint(buf)

  silence_gitsigns(buf)
  M.attach_keymaps(buf)
  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() state[buf] = nil end,
  })

  pcall(vim.cmd, "diffupdate")
  return true
end

--- Number of blocks still waiting on a decision, or nil if this buffer has no
--- result view attached.
function M.unresolved(buf)
  local st = state[buf]
  if not st then return nil end
  local n = 0
  for _, region in ipairs(st.regions) do
    if not region.resolved then n = n + 1 end
  end
  return n
end

function M.attached(buf) return state[buf] ~= nil end

--- Restore the original marker text.
function M.revert(buf)
  buf = buf or api.nvim_get_current_buf()
  local st = state[buf]
  if not st then return false end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, sign_ns, 0, -1)
  api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, st.original)
  state[buf] = nil
  vim.b[buf].merge_result = nil
  pcall(function() require("gitsigns").attach(buf) end)
  pcall(vim.cmd, "diffupdate")
  return true
end

--- The region containing `row`, or nil. Deliberately strict: falling through to
--- "the next block" means an accept key pressed on an ordinary line silently
--- rewrites some other block further down the file.
local function region_at(buf, st, row)
  local last = api.nvim_buf_line_count(buf)
  local empty

  for _, region in ipairs(st.regions) do
    local s, e = range(buf, region)
    if s and e > s then
      if row >= s and row < e then return region end
    elseif s and not empty then
      -- A block dropped to nothing is still selectable on the line it collapsed
      -- onto, so the choice can be taken back -- but only once no block with
      -- real lines wants that line, or c0 would make its neighbour unreachable.
      if row == math.min(s, last - 1) then empty = region end
    end
  end

  return empty
end

--- @param kind "ours"|"theirs"|"both"|"base"|"none"
local function choose(kind)
  local buf = api.nvim_get_current_buf()
  local st = state[buf]
  if not st then return false end

  if has_markers(buf) then
    state[buf] = nil
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, sign_ns, 0, -1)
    api.nvim_buf_clear_namespace(buf, origin_ns, 0, -1)
    vim.notify("Merge: buffer was reloaded with markers -- reopen with :Merge", vim.log.levels.WARN)
    return false
  end

  local region = region_at(buf, st, api.nvim_win_get_cursor(0)[1] - 1)
  if not region then
    vim.notify(
      "Merge: not inside a conflict block (the red bands, bracketed in the gutter) — cn / cp to jump",
      vim.log.levels.WARN)
    return false
  end

  local s, e = range(buf, region)
  if not s then return false end

  local content
  if kind == "ours" then
    content = region.ours
  elseif kind == "theirs" then
    content = region.theirs
  elseif kind == "base" then
    content = region.base or region.ours
  elseif kind == "both" then
    content = vim.list_extend(vim.list_slice(region.ours, 1, #region.ours), region.theirs)
  else
    content = {}
  end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, s, e, false, content)
  api.nvim_buf_del_extmark(buf, ns, region.id)
  region.row, region.len, region.choice, region.resolved = s, #content, kind, true
  place(buf, region)
  repaint(buf)

  pcall(api.nvim_win_set_cursor, 0, { math.min(s + 1, api.nvim_buf_line_count(buf)), 0 })
  pcall(vim.cmd, "diffupdate")
  return true
end

--- Replace the block under the cursor with one of its versions. Works from any
--- of the three panes.
function M.choose(kind)
  return in_result(function() return choose(kind) end)
end

--- Move to the next (dir = 1) or previous (dir = -1) unresolved block, wrapping.
local function jump(dir)
  local buf = api.nvim_get_current_buf()
  local st = state[buf]
  if not st then return false end

  local rows = {}
  for _, region in ipairs(st.regions) do
    if not region.resolved then
      local s = range(buf, region)
      if s then rows[#rows + 1] = s end
    end
  end
  if #rows == 0 then
    vim.notify("Merge: no unresolved blocks left", vim.log.levels.INFO)
    return false
  end
  table.sort(rows)

  local cur = api.nvim_win_get_cursor(0)[1] - 1
  local target
  if dir > 0 then
    for _, row in ipairs(rows) do
      if row > cur then target = row break end
    end
    target = target or rows[1]
  else
    for i = #rows, 1, -1 do
      if rows[i] < cur then target = rows[i] break end
    end
    target = target or rows[#rows]
  end

  api.nvim_win_set_cursor(0, { math.min(target + 1, api.nvim_buf_line_count(buf)), 0 })
  vim.cmd("normal! zz")
  return true
end

--- Jump from any of the three panes; the other two follow, being cursor-bound.
function M.jump(dir)
  return in_result(function() return jump(dir) end)
end

api.nvim_create_user_command("MergeMarkers", function()
  if not M.revert() then
    vim.notify("Merge: this buffer has no result view attached", vim.log.levels.WARN)
  end
end, { desc = "Merge: put the raw conflict markers back in this buffer" })

-- git-conflict.nvim re-registers its own co/ct/cb/c0 on the working file; ours
-- must win in a buffer we transformed (its markers are gone, so its versions
-- would be no-ops).
api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  group = api.nvim_create_augroup("MergeResultKeymaps", { clear = true }),
  callback = function(ev)
    if not state[ev.buf] then return end
    M.attach_keymaps(ev.buf)
    -- gitsigns re-attaches itself on buffer events; keep the gutter meaning
    -- exactly one thing for as long as the result view is up.
    silence_gitsigns(ev.buf)
  end,
})

-- Your own edits move the blocks and change which lines still match a side, so
-- the tints have to follow. Debounced: this runs on every keystroke in insert
-- mode otherwise.
local repaint_timer
api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
  group = api.nvim_create_augroup("MergeResultRepaint", { clear = true }),
  callback = function(ev)
    if not state[ev.buf] then return end
    repaint_timer = repaint_timer or (vim.uv or vim.loop).new_timer()
    repaint_timer:stop()
    repaint_timer:start(150, 0, vim.schedule_wrap(function()
      if api.nvim_buf_is_valid(ev.buf) then repaint(ev.buf) end
    end))
  end,
})

api.nvim_create_autocmd("BufWritePost", {
  group = api.nvim_create_augroup("MergeResultWrite", { clear = true }),
  callback = function(ev)
    local n = M.unresolved(ev.buf)
    if n and n > 0 then
      vim.notify(
        ("Merge: written with %d block%s still undecided (they kept OURS)")
          :format(n, n == 1 and "" or "s"),
        vim.log.levels.WARN)
    end
  end,
})

return M
