-- A list in a centred float: one row per entry, columns lined up, the cursor
-- kept on the same entry across redraws. The Claude session list
-- (claude/picker.lua) and the terminal list (config/termlist.lua) are both one
-- of these.
--
-- It is a plain normal-mode buffer, so moving works like anywhere else:
--   j/k  5j  gg  G  4G  /name   move
--   <C-n> <C-p> <Tab> <S-Tab>   next / previous, wrapping around
--   4<cr>                       act on row 4 directly
--   q / <Esc>                   close; so does going to another window
-- Digits are counts, never "open now": typing 1 waits for the key after it.

local api = vim.api

local M = {}

local ns = api.nvim_create_namespace("MenuFloat")
local current -- only one list is open at a time

--- spec:
---   title      { {text, hl}, ... }       footer, footer_hl   the keys it takes
---   border_hl  border colour             cursor_hl          (default CursorLine)
---   filetype   of the buffer (hardtime is off in "termlist" / "claudelist")
---   rows       fn() -> rows; each row has an `id` naming it across redraws
---   cols       fn(row, index) -> { {text, hl?}, ... }, same count for every row
---   keys       { [lhs] = fn(row, menu) }: row is the count-th one, else the
---              one under the cursor (nil on an empty list)
---   select     id of the row to start on
--- Returns the menu: { refresh(), close(), is_open() }.
function M.open(spec)
  if current then current.close() end
  local m = { rows = {} }
  current = m

  m.buf = api.nvim_create_buf(false, true)
  vim.bo[m.buf].bufhidden = "wipe"
  vim.bo[m.buf].filetype = spec.filetype
  m.win = api.nvim_open_win(m.buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = spec.title, title_pos = "center",
    footer = { { spec.footer, spec.footer_hl or "LineNr" } }, footer_pos = "center",
    width = 40, height = 1, row = 1, col = 1,
  })
  vim.wo[m.win].cursorline = true
  vim.wo[m.win].winhighlight = "FloatBorder:" .. (spec.border_hl or "FloatBorder")
    .. ",CursorLine:" .. (spec.cursor_hl or "CursorLine")

  function m.is_open() return api.nvim_win_is_valid(m.win) end

  function m.close()
    if m.is_open() then api.nvim_win_close(m.win, true) end
    if current == m then current = nil end
  end

  local function cursor_row()
    if not m.is_open() then return end
    return m.rows[api.nvim_win_get_cursor(m.win)[1]]
  end

  --- Redraw; the cursor stays on the row it was on (or on `keep`, an id).
  function m.refresh(keep)
    if not (m.is_open() and api.nvim_buf_is_valid(m.buf)) then return end
    if keep == nil then keep = (cursor_row() or {}).id end
    m.rows = spec.rows()

    local cells, widths = {}, {}
    for i, r in ipairs(m.rows) do
      cells[i] = spec.cols(r, i)
      for j, c in ipairs(cells[i]) do
        widths[j] = math.max(widths[j] or 0, vim.fn.strdisplaywidth(c[1]))
      end
    end

    local lines, marks = {}, {}
    for i, cols in ipairs(cells) do
      local line = " "
      for j, c in ipairs(cols) do
        if c[2] and c[1] ~= "" then marks[#marks + 1] = { i - 1, #line, #line + #c[1], c[2] } end
        line = line .. c[1]
        if j < #cols then
          line = line .. string.rep(" ", widths[j] - vim.fn.strdisplaywidth(c[1]) + 2)
        end
      end
      lines[i] = line:gsub("%s+$", "") .. " "
    end

    vim.bo[m.buf].modifiable = true
    api.nvim_buf_set_lines(m.buf, 0, -1, false, lines)
    vim.bo[m.buf].modifiable = false
    api.nvim_buf_clear_namespace(m.buf, ns, 0, -1)
    for _, mk in ipairs(marks) do
      api.nvim_buf_set_extmark(m.buf, ns, mk[1], mk[2], { end_col = math.min(mk[3], #lines[mk[1] + 1]), hl_group = mk[4] })
    end

    local width = vim.fn.strdisplaywidth(spec.footer) + 2
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
    width = math.min(width, vim.o.columns - 4)
    local height = math.max(1, math.min(#lines, vim.o.lines - 6))
    api.nvim_win_set_config(m.win, {
      relative = "editor", width = width, height = height,
      row = math.floor((vim.o.lines - height) / 2) - 1,
      col = math.floor((vim.o.columns - width) / 2),
    })
    local row = 1
    for i, r in ipairs(m.rows) do if r.id == keep then row = i end end
    api.nvim_win_set_cursor(m.win, { math.min(row, #lines), 0 })
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = m.buf, nowait = true, silent = true })
  end
  for lhs, fn in pairs(spec.keys) do
    map(lhs, function()
      local n = vim.v.count
      fn((n > 0 and m.rows[n]) or cursor_row(), m)
    end)
  end
  local function step(delta)
    return function()
      local n = api.nvim_buf_line_count(m.buf)
      local row = api.nvim_win_get_cursor(m.win)[1]
      api.nvim_win_set_cursor(m.win, { (row - 1 + delta) % n + 1, 0 })
    end
  end
  for _, k in ipairs({ "<C-n>", "<Tab>" }) do map(k, step(1)) end
  for _, k in ipairs({ "<C-p>", "<S-Tab>" }) do map(k, step(-1)) end
  map("q", m.close)
  map("<Esc>", m.close)

  -- Clicking or jumping elsewhere closes it (not a later list that replaced it).
  api.nvim_create_autocmd("WinLeave", {
    buffer = m.buf, once = true,
    callback = function() vim.schedule(function() if current == m then m.close() end end) end,
  })

  m.refresh(spec.select)
  return m
end

return M
