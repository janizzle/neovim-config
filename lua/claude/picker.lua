-- The session list: a small float with an orange border. Every Claude session
-- with its status (most urgent first), then "new" and "resume" rows. It
-- redraws live as sessions change state.
--
-- It is a plain normal-mode buffer, so moving works like anywhere else:
--   j/k  5j  gg  G  4G  /name   move (hardtime is off in here)
--   <C-n> <C-p> <Tab> <S-Tab>   next / previous, wrapping around
--   <cr>   open the row the cursor is on;  4<cr> opens row 4 directly
--   n new · R resume · r rename · d other folder · x stop · q / <Esc> close
-- Digits are counts, never "open now": typing 1 waits for the key after it.

local api = vim.api
local sessions = require("claude.sessions")

local M = {}

M.FILETYPE = "claude_sessions" -- listed in hardtime's disabled_filetypes

local ICON = require("claude.toast").ICON
local ns = api.nvim_create_namespace("ClaudeList")
local KEYS = " <cr> open · 4<cr> row 4 · n new · R resume · r rename · d dir · x stop · <Esc> close "

local L = { win = nil, buf = nil, rows = {} }

local function is_open() return L.win ~= nil and api.nvim_win_is_valid(L.win) end

local function selected()
  if not is_open() then return end
  return L.rows[api.nvim_win_get_cursor(L.win)[1]]
end

local function same(a, b)
  if not (a and b) or a.kind ~= b.kind then return false end
  return a.kind ~= "session" or a.p.id == b.p.id
end

local function pad(s, w) return s .. string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s))) end
local function lpad(s, w) return string.rep(" ", math.max(0, w - vim.fn.strdisplaywidth(s))) .. s end
local function cwd() return vim.fn.fnamemodify(vim.fn.getcwd(), ":~") end

--- Redraw from sessions.list. The cursor stays on `keep` (a row), wherever
--- it moved to; default: the row it is on now.
local function render(keep)
  if not (L.buf and api.nvim_buf_is_valid(L.buf)) then return end
  keep = keep or selected()

  L.rows = {}
  for _, p in ipairs(sessions.list) do L.rows[#L.rows + 1] = { kind = "session", p = p } end
  L.rows[#L.rows + 1] = { kind = "new" }
  L.rows[#L.rows + 1] = { kind = "resume" }

  local num_w = #tostring(#sessions.list)
  local name_w, dir_w = #"New session", 6
  for _, p in ipairs(sessions.list) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(p.name))
    dir_w = math.max(dir_w, vim.fn.strdisplaywidth(p.dir or ""))
  end

  local lines, marks = {}, {}
  for i, r in ipairs(L.rows) do
    local cols -- { {text, hl}, ... }
    if r.kind == "session" then
      local p = r.p
      local _, label, hl = sessions.status(p)
      cols = {
        { " " .. lpad(tostring(i), num_w) .. "  ", "ClaudeDim" },
        { ICON .. " ", "ClaudePanelTitle" },
        { pad(p.name, name_w), "ClaudeBot" .. p.color },
        { "  " .. pad(label, 9), hl },
        { "  " .. pad(p.dir or "", dir_w), "ClaudeDir" },
        { "  " .. (p.topic or ""), "ClaudeTopic" },
        { p.owned and "" or ("  [tmux " .. p.loc .. "]"), "ClaudeDim" },
      }
    else
      local new = r.kind == "new"
      cols = {
        { " " .. lpad(new and "+" or "↺", num_w) .. "  ", new and "ClaudeStatusDone" or "ClaudeStatusBusy" },
        { "  " },
        { pad(new and "New session" or "Resume", name_w), "ClaudeDir" },
        { "  " .. pad("", 9) .. "  " .. pad("", dir_w) },
        { "  " .. (new and ("start Claude in " .. cwd()) or ("pick an earlier conversation in " .. cwd())),
          "ClaudeTopic" },
      }
    end
    local line = ""
    for _, c in ipairs(cols) do
      if c[2] and c[1] ~= "" then marks[#marks + 1] = { i - 1, #line, #line + #c[1], c[2] } end
      line = line .. c[1]
    end
    lines[i] = line .. " "
  end

  vim.bo[L.buf].modifiable = true
  api.nvim_buf_set_lines(L.buf, 0, -1, false, lines)
  vim.bo[L.buf].modifiable = false
  api.nvim_buf_clear_namespace(L.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(L.buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end

  if not is_open() then return end
  local width = vim.fn.strdisplaywidth(KEYS) + 2
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(width, vim.o.columns - 4)
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))
  api.nvim_win_set_config(L.win, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  local row = 1
  for i, r in ipairs(L.rows) do if same(r, keep) then row = i end end
  api.nvim_win_set_cursor(L.win, { row, 0 })
end

function M.close()
  if is_open() then api.nvim_win_close(L.win, true) end
  L.win = nil
end

--- actions = { open(p), new(), resume(), rename(p, done), chdir(p), stop(p, done) }
--- opts.select = pane id to start on (default: the first, most urgent, row).
function M.open(actions, opts)
  opts = opts or {}
  M.close()
  L.buf = api.nvim_create_buf(false, true)
  vim.bo[L.buf].bufhidden = "wipe"
  vim.bo[L.buf].filetype = M.FILETYPE
  L.win = api.nvim_open_win(L.buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = { { " " .. ICON .. " Claude sessions ", "ClaudeToast" } }, title_pos = "center",
    footer = { { KEYS, "ClaudeDim" } }, footer_pos = "center",
    width = 40, height = 1, row = 1, col = 1,
  })
  vim.wo[L.win].cursorline = true
  vim.wo[L.win].winhighlight = "FloatBorder:ClaudeToastBorder,CursorLine:ClaudeListCursor"
  L.rows = {}
  local start = opts.select and sessions.get(opts.select)
  render(start and { kind = "session", p = start })

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = L.buf, nowait = true, silent = true })
  end

  -- Close the list first, then act: the action may open the panel.
  local function activate(r)
    if not r then return end
    M.close()
    if r.kind == "session" then actions.open(r.p)
    elseif r.kind == "new" then actions.new()
    else actions.resume() end
  end
  -- Rename / stop ask in the command line and come back to the list.
  local function on_session(fn, keep_open)
    return function()
      local r = selected()
      if not (r and r.kind == "session") then return end
      if keep_open then return fn(r.p, function() sessions.refresh(function() render() end) end) end
      M.close()
      fn(r.p)
    end
  end
  local function step(delta)
    return function()
      local n = api.nvim_buf_line_count(L.buf)
      local row = api.nvim_win_get_cursor(L.win)[1]
      api.nvim_win_set_cursor(L.win, { (row - 1 + delta) % n + 1, 0 })
    end
  end

  map("<cr>", function()
    local n = vim.v.count
    activate(n > 0 and L.rows[n] or selected())
  end)
  map("o", function() activate(selected()) end)
  map("<2-LeftMouse>", function() activate(selected()) end)
  for _, k in ipairs({ "<C-n>", "<Tab>" }) do map(k, step(1)) end
  for _, k in ipairs({ "<C-p>", "<S-Tab>" }) do map(k, step(-1)) end
  map("n", function() activate({ kind = "new" }) end)
  map("R", function() activate({ kind = "resume" }) end)
  map("r", on_session(actions.rename, true))
  map("x", on_session(actions.stop, true))
  map("d", on_session(actions.chdir))
  map("q", M.close)
  map("<Esc>", M.close)

  -- Clicking or jumping elsewhere closes it (not a later list that replaced it).
  local win = L.win
  api.nvim_create_autocmd("WinLeave", {
    buffer = L.buf, once = true,
    callback = function() vim.schedule(function() if L.win == win then M.close() end end) end,
  })
end

-- Live: states change while the list is up.
sessions.on_scan(function() if is_open() then render() end end)

return M
