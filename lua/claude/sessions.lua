-- Registry of every Claude session: each terminal buffer (config/term.lua)
-- with a Claude process in it. That is the ones <leader>cN starts and any
-- Claude you start yourself in a :term -- through devflow, a script,
-- `claude --resume` -- found by walking the terminal's process tree.
-- Rebuilt every couple of seconds.
--
-- Name and colour live on the buffer (b:claude_name / b:claude_color), so a
-- Claude that exits and comes back in the same terminal keeps them.
--
-- State comes from the bottom of the screen: "esc to interrupt" means it is
-- working, a selection prompt means it is asking you something, anything else
-- is idle. Turning idle after working means it is done.

local api = vim.api
local term = require("config.term")

local M = {}

M.NAMES = {
  "Azure", "Basil", "Orchid", "Teal", "Saffron", "Rosa", "Mint", "Amber",
  "Lilac", "Sage", "Coral", "Indigo", "Juniper", "Maple", "Nova", "Olive",
  "Pepper", "Quartz", "Rowan", "Sky", "Thyme", "Umber", "Violet", "Willow",
}

-- One colour per session, cycled. Orange is left out: it means "needs you".
M.COLORS = {
  "#61AFEF", "#98C379", "#C678DD", "#56B6C2", "#E5C07B",
  "#E06C75", "#7FDBCA", "#D19A66", "#B48EAD", "#A3BE8C",
}

-- Process names (basename of ps comm) that count as Claude. Homebrew's build
-- reports "claude.exe"; the nix wrapper ".claude-wrapped".
M.commands = { claude = true, ["claude.exe"] = true, [".claude-wrapped"] = true }

local patterns = {
  -- Lua patterns matched against the last lines of the screen
  busy = { "esc to interrupt" },
  question = { "Do you want to", "❯ %d+%.", "Enter to select", "Esc to cancel" },
}

M.list = {}     -- last scan, most urgent first
M.by_buf = {}
M.unread = {}   -- buf -> "question" | "done": something you haven't looked at
local state = {}   -- buf -> "question" | "busy" | "idle" from the last scan
local listeners = {}
local scanning, waiting = false, {}

--- fn(list, events) after every scan; events = { {session, kind}, ... } with
--- kind "question" or "done", for the transitions that just happened.
function M.on_scan(fn) listeners[#listeners + 1] = fn end

--- `lines`: the end of the terminal buffer. The screen's unused rows below
--- the content are blank lines there (a fresh Claude sits at the top of an
--- empty screen), so look at the last lines that say anything.
local function classify(lines)
  local text = vim.tbl_filter(function(l) return vim.trim(l) ~= "" end, lines)
  local tail = table.concat(text, "\n", math.max(1, #text - 14))
  for _, p in ipairs(patterns.question) do if tail:find(p) then return "question" end end
  for _, p in ipairs(patterns.busy) do if tail:find(p) then return "busy" end end
  return "idle"
end

--- Claude sets the terminal title to "<glyph> <topic of the conversation>":
--- the glyph is ✳ when idle and a spinner frame while working. Plain
--- "Claude Code" means no conversation yet.
local function topic(title)
  local glyph, rest = (title or ""):match("^([^%w%s]+)%s+(.-)%s*$")
  if not glyph or rest == "" or rest == "Claude Code" then return nil end
  return rest
end

-- Processes -------------------------------------------------------------------

--- cb(children, comm): pid -> child pids, pid -> process name.
local function processes(cb)
  vim.system({ "ps", "-A", "-o", "pid=,ppid=,comm=" }, { text = true }, function(r)
    local children, comm = {}, {}
    if r.code == 0 then
      for line in r.stdout:gmatch("[^\n]+") do
        local pid, ppid, c = line:match("^%s*(%d+)%s+(%d+)%s+(.-)%s*$")
        if pid then
          pid, ppid = tonumber(pid), tonumber(ppid)
          comm[pid] = vim.fs.basename(c)
          children[ppid] = children[ppid] or {}
          table.insert(children[ppid], pid)
        end
      end
    end
    vim.schedule(function() cb(children, comm) end)
  end)
end

--- The Claude process at or below `root`, nearest first.
local function find_claude(root, children, comm)
  local queue, i = { root }, 1
  while queue[i] and i <= 256 do
    local pid = queue[i]
    if M.commands[comm[pid] or ""] then return pid end
    vim.list_extend(queue, children[pid] or {})
    i = i + 1
  end
end

--- cb(dir): the working directory of `pid`, where its relative paths start.
local function cwd_of(pid, cb)
  local link = vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
  if link then return cb(link) end
  vim.system({ "lsof", "-a", "-p", tostring(pid), "-d", "cwd", "-Fn" }, { text = true }, function(r)
    local dir = r.code == 0 and r.stdout:match("\nn([^\n]+)") or nil
    vim.schedule(function() cb(dir) end)
  end)
end

-- Names & colours -------------------------------------------------------------

function M.free_name(list)
  local used = {}
  for _, p in ipairs(list or M.list) do
    if p.name then used[p.name:lower()] = true end
  end
  for _, n in ipairs(M.NAMES) do
    if not used[n:lower()] then return n end
  end
  local i = #M.NAMES + 1
  while used[("claude " .. i)] do i = i + 1 end
  return "Claude " .. i
end

--- The colour fewest live sessions use (lowest index on a tie).
function M.free_color(list)
  local count = {}
  for _, p in ipairs(list or M.list) do
    if p.color then count[p.color] = (count[p.color] or 0) + 1 end
  end
  local best, best_n = 1, math.huge
  for i = 1, #M.COLORS do
    if (count[i] or 0) < best_n then best, best_n = i, count[i] or 0 end
  end
  return best
end

--- Give every session without a name or colour one, kept on its buffer.
local function assign_identity(list)
  local named = vim.tbl_filter(function(p) return p.name ~= nil end, list)
  for _, p in ipairs(list) do
    if not p.name then
      p.name = M.free_name(named)
      named[#named + 1] = p
      vim.b[p.buf].claude_name = p.name
    end
    if not (p.color and M.COLORS[p.color]) then
      p.color = M.free_color(named)
      vim.b[p.buf].claude_color = p.color
    end
  end
end

-- Status ----------------------------------------------------------------------

local ORDER = { question = 1, done = 2, busy = 3, idle = 4 }

--- key, label, highlight group
function M.status(p)
  if p.state == "question" then return "question", "needs you", "ClaudeStatusQuestion" end
  if p.state == "busy" then return "busy", "working", "ClaudeStatusBusy" end
  if M.unread[p.buf] == "done" then return "done", "done", "ClaudeStatusDone" end
  return "idle", "idle", "ClaudeStatusIdle"
end

function M.get(buf) return buf and M.by_buf[buf] end

function M.find(name)
  name = name:lower()
  for _, p in ipairs(M.list) do
    if p.name:lower() == name then return p end
  end
end

function M.mark_seen(buf)
  if M.unread[buf] then M.unread[buf] = nil end
end

--- Change a session's name.
function M.rename(p, name)
  p.name = name
  vim.b[p.buf].claude_name = name
  pcall(vim.cmd, "redrawstatus!")
end

-- Scanning --------------------------------------------------------------------

local function finish(list, events)
  table.sort(list, function(a, b)
    local ka, kb = ORDER[(M.status(a))], ORDER[(M.status(b))]
    if ka ~= kb then return ka < kb end
    return a.name:lower() < b.name:lower()
  end)
  M.list = list
  M.by_buf = {}
  for _, p in ipairs(list) do M.by_buf[p.buf] = p end
  for _, fn in ipairs(listeners) do pcall(fn, list, events) end
  pcall(vim.cmd, "redrawstatus!")  -- the winbars show each session's status

  scanning = false
  local cbs = waiting
  waiting = {}
  for _, cb in ipairs(cbs) do cb(list) end
end

--- One session from a terminal with Claude (pid) in it.
local function session(buf, pid)
  local b = vim.b[buf]
  local p = {
    buf = buf, pid = pid, name = b.claude_name, color = b.claude_color,
    owned = b.claude_owned == true, path = b.claude_dir,
  }
  -- Ask where a Claude you started yourself runs, once per process.
  if b.claude_dir_pid ~= pid and not p.owned then
    vim.b[buf].claude_dir_pid = pid
    cwd_of(pid, function(dir)
      if dir and api.nvim_buf_is_valid(buf) then vim.b[buf].claude_dir = dir end
    end)
  end
  p.dir = p.path and vim.fn.fnamemodify(p.path, ":t") or nil
  p.topic = topic(b.term_title)
  -- A screen's worth and then some: content can sit at its top.
  p.state = classify(api.nvim_buf_get_lines(buf, -(vim.o.lines + 20), -1, false))
  return p
end

--- Rescan now; cb(list) once it is done. Scans never overlap: a call during
--- one just waits for it.
function M.refresh(cb)
  if cb then waiting[#waiting + 1] = cb end
  if scanning then return end
  scanning = true

  processes(function(children, comm)
    local list, events = {}, {}
    for _, buf in ipairs(term.list()) do
      if term.running(buf) then
        local ok, root = pcall(vim.fn.jobpid, term.job(buf))
        local pid = ok and find_claude(root, children, comm)
        -- One we started is Claude itself, even before ps sees its name.
        if not pid and ok and vim.b[buf].claude_owned then pid = root end
        if pid then list[#list + 1] = session(buf, pid) end
      end
    end
    assign_identity(list)

    for _, p in ipairs(list) do
      local old = state[p.buf]
      state[p.buf] = p.state
      if p.state ~= old then
        if p.state == "question" then
          M.unread[p.buf] = "question"
          events[#events + 1] = { p, "question" }
        elseif p.state == "idle" and old == "busy" then
          M.unread[p.buf] = "done"
          events[#events + 1] = { p, "done" }
        elseif p.state == "busy" then
          M.unread[p.buf] = nil -- working again
        elseif M.unread[p.buf] == "question" then
          M.unread[p.buf] = nil -- question answered, went straight to idle
        end
      end
    end

    local alive = {}
    for _, p in ipairs(list) do alive[p.buf] = true end
    for buf in pairs(state) do if not alive[buf] then state[buf] = nil end end
    for buf in pairs(M.unread) do if not alive[buf] then M.unread[buf] = nil end end
    finish(list, events)
  end)
end

local timer
function M.start(interval)
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(500, interval, vim.schedule_wrap(function() M.refresh() end))
end

--- Every terminal with what we make of it, to tune the patterns.
function M.debug()
  local lines = {}
  for _, buf in ipairs(term.list()) do
    local p = M.by_buf[buf]
    lines[#lines + 1] = ("buf %d  %s  %s  %s"):format(buf, term.name(buf),
      term.running(buf) and "running" or "exited",
      p and ("claude %s pid %d [%s] %s"):format(p.name, p.pid, p.state, p.path or "?") or "-")
  end
  vim.notify(#lines > 0 and table.concat(lines, "\n") or "No terminals", vim.log.levels.INFO,
    { title = "Claude terminals" })
end

return M
