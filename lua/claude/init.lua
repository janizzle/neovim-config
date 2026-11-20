-- Claude Code inside Neovim.
--
-- A Claude session is a terminal like any other (config/term.lua): an
-- ordinary split, <Esc> for normal mode over the whole conversation, <C-q> to
-- hide it while it keeps working. Start as many as you like. A Claude you
-- start yourself in a :term (devflow, a script, `claude --resume`) is picked
-- up too and gets a name, a colour and a live status in its title bar.
--
-- You get a toast when a session has a question or finishes, and the
-- statusline counts what is waiting for you. Sessions end with Neovim; the
-- "Resume" row in the list (claude --resume) picks a conversation up again.
--
--   <leader>cc  the session list (also :Claude / :claude)
--   <leader>cN  new session            <leader>ch  show / hide Claude
--   <leader>cy  send the selection (or line) -- file, lines, code -- plus a comment
-- Plain terminals have their own list: :term / <leader>tt (config/termlist.lua).
--
-- Commands: :Claude (list) :ClaudeNew [name] :ClaudeResume :ClaudeOpen [name]
--           :ClaudeClose :ClaudeRename [name] :ClaudeSend :ClaudeDebug

local api = vim.api
local term = require("config.term")
local sessions = require("claude.sessions")
local picker = require("claude.picker")
local toast = require("claude.toast")

local M = {}

local cfg = {
  interval = 2000, -- ms between scans
  toast_ms = { question = 10000, done = 6000 },
}

local last -- buffer of the session you used last: shown, typed in, sent to

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN, { title = "Claude" })
end

local function define_highlights()
  local C = require("config.palette")
  local set = function(n, o) api.nvim_set_hl(0, n, o) end
  set("ClaudeToast", { fg = C.claude, bg = C.bg_alt, bold = true })
  set("ClaudeToastBorder", { fg = C.claude, bg = C.bg_alt })
  set("ClaudeToastDim", { fg = C.unused, bg = C.bg_alt })
  set("ClaudeStatusQuestion", { fg = C.claude, bold = true })
  set("ClaudeStatusDone", { fg = C.green, bold = true })
  set("ClaudeStatusBusy", { fg = C.blue })
  set("ClaudeStatusIdle", { fg = C.line_nr })
  set("ClaudeDim", { fg = C.line_nr })
  set("ClaudeDir", { fg = C.fg })
  set("ClaudeTopic", { fg = C.unused, italic = true })
  set("ClaudePanelTitle", { fg = C.claude, bold = true })
  set("ClaudeListCursor", { bg = C.bg_sel })
  for i, c in ipairs(sessions.COLORS) do
    set("ClaudeBot" .. i, { fg = c, bold = true })
  end
end

local function claude_bin()
  local bin = vim.fn.exepath("claude")
  if bin == "" then return notify("`claude` is not on your PATH") end
  return bin
end

-- Sessions --------------------------------------------------------------------

--- Start a session and show it on the right. Asks for a name (Enter takes the
--- suggested one) unless opts.name is given; opts.args (a list) go to
--- `claude`, opts.dir is where it runs (default: the cwd).
function M.new(opts)
  opts = opts or {}
  local bin = claude_bin()
  if not bin then return end

  local function start(name)
    name = vim.trim(name or "")
    if name == "" then return end
    if sessions.find(name) then return notify("There already is a session called " .. name) end
    local dir = opts.dir or vim.fn.getcwd()
    local buf = term.new(vim.list_extend({ bin }, opts.args or {}), {
      home = "right", dir = dir, close_on_exit = true,
      vars = {
        claude_name = name, claude_color = sessions.free_color(),
        claude_owned = true, claude_dir = dir,
      },
    })
    if buf then
      last = buf
      sessions.refresh()
    end
  end

  if opts.name then return start(opts.name) end
  vim.ui.input({ prompt = "New Claude session, name: ", default = sessions.free_name() }, start)
end

--- Start a session somewhere other than the cwd.
function M.new_in_dir()
  vim.ui.input({ prompt = "New Claude session in: ", default = vim.fn.getcwd(), completion = "dir" },
    function(dir)
      if not dir or vim.trim(dir) == "" then return end
      dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(dir)), ":p")
      if vim.fn.isdirectory(dir) == 0 then return notify("Not a directory: " .. dir, vim.log.levels.ERROR) end
      M.new({ dir = dir })
    end)
end

function M.rename(p, done)
  vim.ui.input({ prompt = "Rename " .. p.name .. " to: ", default = p.name }, function(name)
    name = vim.trim(name or "")
    local other = name ~= "" and sessions.find(name)
    if other and other.buf ~= p.buf then
      notify("There already is a session called " .. name)
    elseif name ~= "" and name ~= p.name then
      sessions.rename(p, name)
    end
    if done then done() end
  end)
end

--- A session you started here goes with its terminal; a Claude you started
--- yourself (devflow, ...) is stopped and its terminal stays.
function M.stop(p, done)
  local what = p.owned and "" or " (its terminal stays open)"
  if vim.fn.confirm("Stop Claude " .. p.name .. what .. "?", "&Stop\n&Cancel", 2) == 1 then
    if p.owned then term.kill(p.buf) else pcall(vim.uv.kill, p.pid, "sigterm") end
  end
  if done then done() else sessions.refresh() end
end

--- Is `buf` a Claude session (also one started a moment ago, before a scan)?
local function is_session(buf)
  return sessions.by_buf[buf] ~= nil or (term.is_term(buf) and vim.b[buf].claude_owned == true)
end

--- Show `p` (a session or its name) and go into it. Without one: the session
--- you used last, the only one there is, or a choice -- or a new one when
--- there are none.
function M.open(p)
  if type(p) == "string" then
    local found = sessions.find(p)
    if not found then return notify("No Claude session called " .. p) end
    p = found
  end
  if p then
    last = p.buf
    return term.show(p.buf)
  end
  if last and is_session(last) then return term.show(last) end
  sessions.refresh(function(list)
    if #list == 0 then return M.new() end
    if #list == 1 then return M.open(list[1]) end
    M.list()
  end)
end

--- Windows in this tabpage that show a Claude session.
local function claude_windows()
  local out = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_session(api.nvim_win_get_buf(win)) then out[#out + 1] = win end
  end
  return out
end

--- Hide every Claude on screen; they keep running.
function M.close()
  for _, win in ipairs(claude_windows()) do term.hide(win) end
end

function M.toggle()
  if #claude_windows() > 0 then M.close() else M.open() end
end

-- Sending code ----------------------------------------------------------------

--- What to send: the selection, else the :range, else the cursor line.
local function grab(range)
  local mode = api.nvim_get_mode().mode
  local first, last_line, lines
  if mode:match("^[vV\22]") then
    local vs, ve = vim.fn.getpos("v"), vim.fn.getpos(".")
    lines = vim.fn.getregion(vs, ve, { type = mode })
    first, last_line = math.min(vs[2], ve[2]), math.max(vs[2], ve[2])
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  elseif range and range.range > 0 then
    first, last_line = range.line1, range.line2
    lines = api.nvim_buf_get_lines(0, first - 1, last_line, false)
  else
    first = api.nvim_win_get_cursor(0)[1]
    last_line = first
    lines = { api.nvim_get_current_line() }
  end
  return {
    file = api.nvim_buf_get_name(0), ft = vim.bo.filetype,
    first = first, last = last_line, lines = lines,
  }
end

--- `file` as the session sees it: relative to where it runs if it is inside,
--- else the full path.
local function path_for(file, base)
  if file == "" then return "[unsaved buffer]" end
  local abs = vim.uv.fs_realpath(file) or vim.fn.fnamemodify(file, ":p")
  local root = base and vim.uv.fs_realpath(base)
  return (root and vim.fs.relpath(root, abs)) or abs
end

--- path:12-30, then the code fenced (longer than any fence inside it), then
--- the comment. Lines are joined with CR, the way a terminal pastes them.
local function message(sel, p, comment)
  local longest = 2
  for _, l in ipairs(sel.lines) do
    for run in l:gmatch("`+") do longest = math.max(longest, #run) end
  end
  local fence = string.rep("`", longest + 1)
  local range = sel.first == sel.last and tostring(sel.first) or (sel.first .. "-" .. sel.last)
  local out = { path_for(sel.file, p.path) .. ":" .. range, fence .. sel.ft }
  vim.list_extend(out, sel.lines)
  out[#out + 1] = fence
  out[#out + 1] = ""
  if comment ~= "" then out[#out + 1] = comment end
  return table.concat(out, "\r")
end

--- Paste into the session as one bracketed paste, so newlines in the code
--- stay newlines in Claude's prompt instead of sending it line by line.
local function paste(p, text, submit)
  local job = term.job(p.buf)
  if not (job and term.running(p.buf)) then return notify(p.name .. " is not running") end
  api.nvim_chan_send(job, "\27[200~" .. text .. "\27[201~")
  if submit then
    -- After Claude has taken the paste in, or the Enter lands inside it.
    vim.defer_fn(function()
      if term.running(p.buf) then api.nvim_chan_send(job, "\r") end
    end, 150)
  end
end

--- cb(session): the only one, else a choice with the one you used last on top.
local function choose(cb)
  sessions.refresh(function(list)
    if #list == 0 then return notify("No Claude session running (<leader>cN starts one)") end
    if #list == 1 then return cb(list[1]) end
    local items = {}
    for _, p in ipairs(list) do
      if p.buf == last then table.insert(items, 1, p) else items[#items + 1] = p end
    end
    vim.ui.select(items, {
      prompt = "Send to which Claude?",
      format_item = function(p)
        local _, label = sessions.status(p)
        return ("%s · %s · %s%s"):format(p.name, label, p.dir or "?", p.topic and (" · " .. p.topic) or "")
      end,
    }, function(p) if p then cb(p) end end)
  end)
end

--- Send the selection (or :range, or the cursor line) with its file and line
--- numbers to a session, plus a comment. With a comment it is sent right
--- away and you stay in the code; with none it lands in Claude's prompt and
--- you go there to keep typing.
function M.send(range)
  local sel = grab(range)
  choose(function(p)
    vim.ui.input({ prompt = ("→ %s  comment (empty: keep typing in Claude): "):format(p.name) }, function(comment)
      if comment == nil then return end -- <Esc>: cancelled
      comment = vim.trim(comment)
      last = p.buf
      local submit = comment ~= ""
      paste(p, message(sel, p, comment), submit)
      if submit then
        local n = sel.last - sel.first + 1
        api.nvim_echo({ { "Sent " .. n .. (n == 1 and " line" or " lines") .. " to ", "ClaudeDim" },
          { p.name, "ClaudeBot" .. p.color } }, false, {})
      else
        vim.b[p.buf].term_typing = true
        term.show(p.buf)
      end
    end)
  end)
end

-- Session list ------------------------------------------------------------------

local actions = {
  open = function(p) M.open(p) end,
  new = function() M.new() end,
  resume = function() M.new({ args = { "--resume" } }) end,
  new_in_dir = M.new_in_dir,
  rename = function(p, done) M.rename(p, done) end,
  stop = function(p, done) M.stop(p, done) end,
}

--- The session list, live.
function M.list()
  local function show()
    local cur = api.nvim_get_current_buf()
    picker.open(actions, is_session(cur) and cur or last)
  end
  if #sessions.list > 0 then return show() end
  sessions.refresh(show) -- first use: wait for the first scan
end

-- Statusline ------------------------------------------------------------------

local function unread_counts()
  local q, d = 0, 0
  for _, kind in pairs(sessions.unread) do
    if kind == "question" then q = q + 1 else d = d + 1 end
  end
  return q, d
end

--- "󰚩 1 waiting · 2 done", or "" when nothing is waiting for you.
function M.statusline()
  local q, d = unread_counts()
  local parts = {}
  if q > 0 then parts[#parts + 1] = q .. " waiting" end
  if d > 0 then parts[#parts + 1] = d .. " done" end
  if #parts == 0 then return "" end
  return toast.ICON .. " " .. table.concat(parts, " · ")
end

function M.statusline_color()
  local C = require("config.palette")
  return { fg = (unread_counts()) > 0 and C.claude or C.green, gui = "bold" }
end

-- Setup -----------------------------------------------------------------------

local function alert(p, kind)
  -- You are looking right at it: nothing to tell.
  if api.nvim_get_current_buf() == p.buf then
    sessions.mark_seen(p.buf)
    return
  end
  local chunks = {
    { p.name, "ClaudeBot" .. p.color },
    { kind == "question" and " has a question" or " is done" },
    { "  " .. (p.topic or p.dir or ""), "ClaudeToastDim" },
  }
  toast.show(chunks, cfg.toast_ms[kind])
end

--- Title bar of a session's window: who it is, what it is doing, where.
local function winbar(buf)
  local p = sessions.by_buf[buf]
  if not p then return nil end
  local _, label, hl = sessions.status(p)
  return {
    { toast.ICON .. " ", "ClaudePanelTitle" },
    { p.name, "ClaudeBot" .. p.color },
    { "  " .. label, hl },
    { p.dir and ("  " .. p.dir) or "", "ClaudeDir" },
    { p.topic and ("  " .. p.topic) or "", "ClaudeTopic" },
  }
end

local function complete_names(lead)
  local out = {}
  for _, p in ipairs(sessions.list) do
    if p.name:lower():find(lead:lower(), 1, true) == 1 then out[#out + 1] = p.name end
  end
  return out
end

local function current_session()
  return sessions.get(api.nvim_get_current_buf()) or sessions.get(last)
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", cfg, opts or {})
  define_highlights()
  api.nvim_create_autocmd("ColorScheme", { callback = define_highlights })
  api.nvim_create_autocmd("VimResized", { callback = toast.layout })

  table.insert(term.title_providers, winbar)
  table.insert(term.owners, is_session) -- listed here, not in the terminal list
  sessions.on_scan(function(_, events)
    for _, e in ipairs(events) do alert(e[1], e[2]) end
  end)
  -- Looking at a session counts as reading it.
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    callback = function()
      local buf = api.nvim_get_current_buf()
      if is_session(buf) then
        last = buf
        sessions.mark_seen(buf)
      end
    end,
  })

  -- On <leader>c, next to the code keys there (ca ci cs cd cf, cn/cp hunks).
  local map = function(mode, lhs, fn, desc) vim.keymap.set(mode, lhs, fn, { desc = desc }) end
  map("n", "<leader>cc", M.list, "Claude: sessions")
  map("n", "<leader>cN", function() M.new() end, "Claude: new session")
  map("n", "<leader>ch", M.toggle, "Claude: show / hide")
  map({ "n", "x" }, "<leader>cy", function() M.send() end, "Claude: send selection / line + comment")

  local cmd = api.nvim_create_user_command
  cmd("Claude", M.list, { desc = "Claude sessions (list)" })
  -- :claude, typed on its own, means the same.
  vim.cmd([[cnoreabbrev <expr> claude (getcmdtype() == ':' && getcmdline() ==# 'claude') ? 'Claude' : 'claude']])
  cmd("ClaudeToggle", M.toggle, { desc = "Show / hide Claude" })
  cmd("ClaudeOpen", function(o) M.open(o.args ~= "" and o.args or nil) end,
    { nargs = "?", complete = complete_names, desc = "Show a Claude session" })
  cmd("ClaudeClose", M.close, { desc = "Hide Claude (sessions keep running)" })
  cmd("ClaudeNew", function(o) M.new({ name = o.args ~= "" and o.args or nil }) end,
    { nargs = "?", desc = "Start a Claude session in the cwd" })
  cmd("ClaudeResume", function() M.new({ args = { "--resume" } }) end,
    { desc = "Start a Claude session that picks up an earlier conversation" })
  cmd("ClaudeSend", function(o) M.send(o) end,
    { range = true, desc = "Send the lines (with file and line numbers) to a Claude session" })
  cmd("ClaudeRename", function(o)
    local p = current_session()
    if not p then return notify("No session to rename; rename from :ClaudeList") end
    if o.args ~= "" then
      local other = sessions.find(o.args)
      if other and other.buf ~= p.buf then return notify("There already is a session called " .. o.args) end
      sessions.rename(p, o.args)
    else
      M.rename(p)
    end
  end, { nargs = "?", desc = "Rename the current Claude session" })
  cmd("ClaudeDebug", sessions.debug, { desc = "Show every terminal and its Claude state" })

  sessions.start(cfg.interval)
end

return M
