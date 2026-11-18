-- Registry of every Claude session, rebuilt by polling tmux.
--
-- Each session is a tmux pane. Its name and colour are stored on the pane
-- itself (@claude_name / @claude_color), so they stay put for the pane's whole
-- life and every Neovim agrees on them. A pane that has none yet -- a Claude
-- you started by hand -- gets the first free name from NAMES when it is first
-- seen; after that, any name you give it sticks.
--
-- State comes from the bottom of the screen: "esc to interrupt" means it is
-- working, a selection prompt means it is asking you something, anything else
-- is idle. Turning idle after working means it is done.

local tmux = require("claude.tmux")

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

local patterns = {
  -- Lua patterns matched against the last lines of the pane
  busy = { "esc to interrupt" },
  question = { "Do you want to", "❯ %d+%.", "Enter to select", "Esc to cancel" },
}

M.list = {}     -- last scan, most urgent first
M.by_id = {}
M.unread = {}   -- pane id -> "question" | "done": something you haven't looked at
local state = {}   -- pane id -> "question" | "busy" | "idle" from the last scan
local listeners = {}
local scanning, waiting = false, {}

--- fn(list, events) after every scan; events = { {session, kind}, ... } with
--- kind "question" or "done", for the transitions that just happened.
function M.on_scan(fn) listeners[#listeners + 1] = fn end

local function classify(text)
  local lines = vim.split(text, "\n", { trimempty = true })
  local tail = table.concat(lines, "\n", math.max(1, #lines - 14))
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

--- Give every unnamed pane a name and colour, and store them on the pane.
local function assign_identity(list)
  for _, p in ipairs(list) do
    if p.color and (p.color < 1 or p.color > #M.COLORS) then p.color = nil end
  end
  local named = vim.tbl_filter(function(p) return p.name ~= nil end, list)
  for _, p in ipairs(list) do
    local opts = {}
    if not p.name then
      p.name = M.free_name(named)
      named[#named + 1] = p
      opts.claude_name = p.name
    end
    if not p.color then
      p.color = M.free_color(named)
      opts.claude_color = p.color
    end
    if next(opts) then tmux.set_pane_options(p.id, opts) end
  end
end

-- Status ----------------------------------------------------------------------

local ORDER = { question = 1, done = 2, busy = 3, idle = 4 }

--- key, label, highlight group
function M.status(p)
  if p.state == "question" then return "question", "needs you", "ClaudeStatusQuestion" end
  if p.state == "busy" then return "busy", "working", "ClaudeStatusBusy" end
  if M.unread[p.id] == "done" then return "done", "done", "ClaudeStatusDone" end
  return "idle", "idle", "ClaudeStatusIdle"
end

function M.get(id) return M.by_id[id] end

function M.find(name)
  name = name:lower()
  for _, p in ipairs(M.list) do
    if p.name:lower() == name then return p end
  end
end

function M.mark_seen(id)
  if M.unread[id] then M.unread[id] = nil end
end

--- Change a session's name everywhere at once.
function M.rename(p, name)
  p.name = name
  tmux.set_pane_options(p.id, { claude_name = name })
end

-- Scanning --------------------------------------------------------------------

local function finish(list, events)
  table.sort(list, function(a, b)
    local ka, kb = ORDER[(M.status(a))], ORDER[(M.status(b))]
    if ka ~= kb then return ka < kb end
    return a.name:lower() < b.name:lower()
  end)
  M.list = list
  M.by_id = {}
  for _, p in ipairs(list) do M.by_id[p.id] = p end
  for _, fn in ipairs(listeners) do pcall(fn, list, events) end

  scanning = false
  local cbs = waiting
  waiting = {}
  for _, cb in ipairs(cbs) do cb(list) end
end

--- Rescan now; cb(list) once it is done. Scans never overlap: a call during
--- one just waits for it.
function M.refresh(cb)
  if cb then waiting[#waiting + 1] = cb end
  if scanning then return end
  scanning = true

  tmux.claude_panes(function(list)
    assign_identity(list)
    local left = #list
    local events = {}
    if left == 0 then
      state, M.unread = {}, {}
      return finish(list, events)
    end

    for _, p in ipairs(list) do
      p.dir = vim.fn.fnamemodify(p.path, ":t")
      p.topic = topic(p.title)
      tmux.capture(p.id, function(text)
        p.state = text ~= "" and classify(text) or "idle"
        local old = state[p.id]
        state[p.id] = p.state
        if p.state ~= old then
          if p.state == "question" then
            M.unread[p.id] = "question"
            events[#events + 1] = { p, "question" }
          elseif p.state == "idle" and old == "busy" then
            M.unread[p.id] = "done"
            events[#events + 1] = { p, "done" }
          elseif p.state == "busy" then
            M.unread[p.id] = nil -- answered elsewhere / working again
          elseif M.unread[p.id] == "question" then
            M.unread[p.id] = nil -- question answered, went straight to idle
          end
        end
        left = left - 1
        if left == 0 then
          local alive = {}
          for _, x in ipairs(list) do alive[x.id] = true end
          for id in pairs(state) do if not alive[id] then state[id] = nil end end
          for id in pairs(M.unread) do if not alive[id] then M.unread[id] = nil end end
          finish(list, events)
        end
      end)
    end
  end)
end

local timer
function M.start(interval)
  if timer then return end
  timer = vim.uv.new_timer()
  timer:start(500, interval, vim.schedule_wrap(function() M.refresh() end))
end

--- Every tmux pane with its tty and what we make of it, to tune the patterns.
function M.debug()
  local ok, out = tmux.run_sync({ "list-panes", "-a", "-F",
    "#{pane_id}\t#{pane_tty}\t#{pane_current_command}\t#{session_name}:#{window_index}.#{pane_index}\t#{@claude_name}\t#{pane_title}" })
  if not ok then return vim.notify("tmux is not running", vim.log.levels.WARN) end
  local lines = {}
  for line in out:gmatch("[^\n]+") do
    local id = line:match("^(%S+)")
    local p = M.by_id[id]
    lines[#lines + 1] = line .. "\t[" .. (p and (p.state or "?") or "-") .. "]"
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Claude panes" })
end

return M
