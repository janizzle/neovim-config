-- Watches tmux panes running Claude Code and notifies you in Neovim when one
-- has a question or finishes. Needs nothing on Claude's side (no hooks,
-- no settings.json), so it works no matter how Claude is sandboxed.
-- Requires Neovim 0.10+ and Claude running in a pane of the same tmux server.
--
--   <leader>cc   list every Claude session with its status, open one
--   in the popup: a = answer, r = refresh, q = close
--   answer "2"          -> picks menu option 2
--   answer "2 some text" -> picks option 2, then types "some text" + Enter
--   answer "some text"  -> types it + Enter
--   multi-select menu:   "1,3" / "1 3" -> checks those boxes, then Submit

local C = require("config.palette")

local M = { items = {}, panes = {} }

local cfg = {
  key = "<leader>cc",
  interval = 2000, -- ms between scans
  -- process names (ps comm) on a pane's tty that count as Claude. The nix
  -- wrapper makes pane_current_command say "bash", so we look at all processes.
  commands = { "claude", ".claude-wrapped" },
  -- Lua patterns matched against the bottom of the pane
  busy = { "esc to interrupt" },
  question = { "Do you want to", "❯ %d+%.", "Enter to select", "Esc to cancel" },
  select_delay = 300, -- ms between picking a menu number and typing the text
  toast_ms = { question = 10000, done = 6000 },
  -- One colour per bot number (1-10). Orange is left out: it means "needs you".
  -- One name per bot number (1-10), same order as bot_colors.
  bot_names = {
    "Azure", "Basil", "Orchid", "Teal", "Saffron",
    "Rosa", "Mint", "Amber", "Lilac", "Sage",
  },
  bot_colors = {
    "#61AFEF", "#98C379", "#C678DD", "#56B6C2", "#E5C07B",
    "#E06C75", "#7FDBCA", "#D19A66", "#B48EAD", "#A3BE8C",
  },
}

local icon = vim.fn.nr2char(0xF06A9) -- nf-md-robot

local function is_claude(cmd)
  for _, c in ipairs(cfg.commands) do if cmd == c then return true end end
  return false
end

-- Bot number 1-10 from the tmux pane id (%0 -> 1 ... %9 -> 10, then wraps), so
-- a pane keeps its name and colour for as long as the tmux server lives.
local function bot_num(pane)
  return (tonumber(pane:match("%d+")) or 0) % 10 + 1
end

local function sys(args, cb)
  vim.system(args, { text = true }, function(r) vim.schedule(function() cb(r) end) end)
end

-- Calls cb(set) with the ttys (e.g. "pts/2") that have a Claude process on them
local function claude_ttys(cb)
  sys({ "ps", "-eo", "tty=,comm=" }, function(r)
    local set = {}
    if r.code == 0 then
      for line in r.stdout:gmatch("[^\n]+") do
        local tty, comm = line:match("^%s*(%S+)%s+(.-)%s*$")
        if tty and is_claude(comm) then set[tty] = true end
      end
    end
    cb(set)
  end)
end

local function drop(pane)
  M.items = vim.tbl_filter(function(x) return x.pane ~= pane end, M.items)
end

local function pending(pane)
  for _, x in ipairs(M.items) do if x.pane == pane then return x end end
end

local function classify(text)
  local lines = vim.split(text, "\n", { trimempty = true })
  local tail = table.concat(lines, "\n", math.max(1, #lines - 14))
  for _, p in ipairs(cfg.question) do if tail:find(p) then return "question" end end
  for _, p in ipairs(cfg.busy) do if tail:find(p) then return "busy" end end
  return "idle"
end

-- Toasts ----------------------------------------------------------------------
-- Small orange floats stacked in the top-right corner; vim.notify's default is
-- a one-line echo that is gone by the next redraw.

local toasts = {}

local function layout_toasts()
  local row = 1
  for _, t in ipairs(toasts) do
    if vim.api.nvim_win_is_valid(t.win) then
      vim.api.nvim_win_set_config(t.win, {
        relative = "editor", row = row, col = math.max(vim.o.columns - t.width - 3, 0),
      })
      row = row + 3
    end
  end
end

-- bot = { name = "Claude Azure", num = 1 }: colours that name inside the toast
local function toast(text, ms, hl, bot)
  hl = hl or "ClaudeToast"
  local prefix = " " .. icon .. "  "
  local line = prefix .. text .. " "
  local width = vim.fn.strdisplaywidth(line)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", row = 1, col = math.max(vim.o.columns - width - 3, 0),
    width = width, height = 1, style = "minimal", border = "rounded",
    focusable = false, zindex = 250, noautocmd = true,
  })
  vim.wo[win].winhighlight = "NormalFloat:" .. hl .. ",FloatBorder:" .. hl .. "Border"
  if bot and text:sub(1, #bot.name) == bot.name then
    vim.api.nvim_buf_add_highlight(buf, -1, "ClaudeBot" .. bot.num, 0, #prefix, #prefix + #bot.name)
  end
  local t = { win = win, width = width }
  table.insert(toasts, t)
  layout_toasts()
  vim.defer_fn(function()
    for i, x in ipairs(toasts) do if x == t then table.remove(toasts, i) break end end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    layout_toasts()
  end, ms)
end

local function define_highlights()
  vim.api.nvim_set_hl(0, "ClaudeToast", { fg = C.claude, bg = C.bg_alt, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeToastBorder", { fg = C.claude, bg = C.bg_alt })
  vim.api.nvim_set_hl(0, "ClaudeStatusQuestion", { fg = C.claude, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeStatusDone", { fg = C.green })
  vim.api.nvim_set_hl(0, "ClaudeStatusBusy", { fg = C.blue })
  vim.api.nvim_set_hl(0, "ClaudeStatusIdle", { fg = C.line_nr })
  for i, c in ipairs(cfg.bot_colors) do
    vim.api.nvim_set_hl(0, "ClaudeBot" .. i, { fg = c, bold = true })
  end
end

local function add(pane, name, kind, msg)
  drop(pane)
  table.insert(M.items, { pane = pane, name = name, kind = kind, msg = msg })
  local n = bot_num(pane)
  toast(name .. " " .. msg, cfg.toast_ms[kind] or 6000, nil,
    { name = "Claude " .. cfg.bot_names[n], num = n })
end

-- Scanning --------------------------------------------------------------------

local PANE_FMT = "#{pane_id}\t#{pane_tty}\t#{pane_current_path}\t"
  .. "#{session_name}:#{window_index}.#{pane_index}"

-- Calls cb(list) with one {pane,name,loc,state} per Claude pane; state is
-- "question" | "busy" | "idle". Also called by tmux-less setups: cb({}).
local function collect(cb)
  sys({ "tmux", "list-panes", "-a", "-F", PANE_FMT }, function(r)
    if r.code ~= 0 then return cb({}) end
    claude_ttys(function(ttys)
      local found = {}
      for line in r.stdout:gmatch("[^\n]+") do
        local id, tty, path, loc = line:match("^(%S+)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if id and ttys[(tty:gsub("^/dev/", ""))] then
          local n = bot_num(id)
          found[#found + 1] = {
            pane = id, num = n, name = "Claude " .. cfg.bot_names[n],
            dir = vim.fn.fnamemodify(path, ":t"), loc = loc,
          }
        end
      end
      local left = #found
      if left == 0 then return cb({}) end
      for _, p in ipairs(found) do
        sys({ "tmux", "capture-pane", "-p", "-t", p.pane }, function(c)
          p.state = c.code == 0 and classify(c.stdout) or "idle"
          left = left - 1
          if left == 0 then cb(found) end
        end)
      end
    end)
  end)
end

local function scan()
  collect(function(list)
    local alive = {}
    for _, p in ipairs(list) do
      alive[p.pane] = true
      local old = M.panes[p.pane]
      M.panes[p.pane] = p.state
      if p.state ~= old then
        if p.state == "question" then
          add(p.pane, p.name .. " (" .. p.dir .. ")", "question", "has a question")
        elseif p.state == "idle" and old == "busy" then
          add(p.pane, p.name .. " (" .. p.dir .. ")", "done", "is done")
        elseif p.state == "busy" then
          drop(p.pane) -- answered elsewhere / working again
        end
      end
    end
    for id in pairs(M.panes) do
      if not alive[id] then M.panes[id] = nil; drop(id) end
    end
  end)
end

-- Answering -------------------------------------------------------------------

local function send(pane, ...)
  vim.system(vim.list_extend({ "tmux", "send-keys", "-t", pane }, { ... })):wait()
end

-- Reads the on-screen menu. Returns nil unless it is a multi-select (numbered
-- rows with a "[ ]" / "[✔]" box). Rows are in screen order: the options, then
-- the bare "Submit" row below them.
local function multi_menu(pane)
  local out = vim.fn.system({ "tmux", "capture-pane", "-p", "-t", pane })
  local lines = vim.split(out, "\n", { trimempty = true })
  local rows, boxes = {}, 0
  for i = math.max(1, #lines - 29), #lines do
    -- "❯" is multi-byte, so it is stripped as a plain prefix, not a char class
    local cursor = lines[i]:match("^%s*❯") ~= nil
    local body = lines[i]:gsub("^%s*", ""):gsub("^❯%s*", "")
    local num, rest = body:match("^(%d+)%.%s+(.*)$")
    if num then
      local box = rest:match("^%[(.-)%]")
      if box then boxes = boxes + 1 end
      rows[#rows + 1] = {
        num = tonumber(num), cursor = cursor, checked = box ~= nil and box ~= " ",
        other = rest:find("Type something", 1, true) ~= nil, box = box ~= nil,
      }
    elseif body == "Submit" or body == "Next" then
      rows[#rows + 1] = { cursor = cursor, submit = true }
    end
  end
  if boxes == 0 then return nil end
  return { rows = rows }
end

-- "1,3" checks options 1 and 3 (and unchecks any other ticked box); "1,3 some
-- text" also types the text into the "Type something" row. Then Submit + Enter.
local function answer_multi(pane, menu, ans)
  local want, text = {}, nil
  local words = vim.split(vim.trim(ans), "[%s,]+", { trimempty = true })
  for i, w in ipairs(words) do
    if w:match("^%d+$") then want[tonumber(w)] = true
    else text = table.concat(words, " ", i); break end
  end
  local at = 1
  for i, r in ipairs(menu.rows) do if r.cursor then at = i end end
  local steps = {} -- { "Down" | "Up" | "Space" | { "-l", text } }
  local function goto_row(to)
    while at < to do steps[#steps + 1] = "Down"; at = at + 1 end
    while at > to do steps[#steps + 1] = "Up"; at = at - 1 end
  end
  for i, r in ipairs(menu.rows) do
    if r.box and not r.other and (want[r.num] or false) ~= r.checked then
      goto_row(i); steps[#steps + 1] = "Space"
    elseif r.other and text then
      goto_row(i); steps[#steps + 1] = { "-l", text }
    end
  end
  for i, r in ipairs(menu.rows) do if r.submit then goto_row(i) end end
  steps[#steps + 1] = "Enter"
  -- one tmux call, commands chained with ";", so nothing blocks Neovim
  local args = { "tmux" }
  for i, st in ipairs(steps) do
    if i > 1 then args[#args + 1] = ";" end
    vim.list_extend(args, { "send-keys", "-t", pane })
    vim.list_extend(args, type(st) == "table" and st or { st })
  end
  vim.system(args)
end

-- "Sent" goes in the command line, in green (scheduled so the prompt has closed)
local function sent_echo()
  vim.api.nvim_echo({ { "Sent", "ClaudeStatusDone" } }, false, {})
end

local function answer(pane, ans)
  local menu = multi_menu(pane)
  if menu then
    answer_multi(pane, menu, ans)
    drop(pane)
    return vim.schedule(sent_echo)
  end
  local num, text = ans:match("^(%d%d?)%s+(.+)$")
  if num then
    send(pane, num)                       -- select the menu option ...
    vim.defer_fn(function()               -- ... let its text field open, then type
      send(pane, "-l", text)
      send(pane, "Enter")
    end, cfg.select_delay)
  elseif ans:match("^%d%d?$") then
    send(pane, ans)                       -- menu option only: the digit selects it
  else
    if ans ~= "" then send(pane, "-l", ans) end
    send(pane, "Enter")                   -- text answer / accept default
  end
  drop(pane)
  -- scheduled so it opens after the cmdline prompt has fully closed
  vim.schedule(sent_echo)
end

function M.open(it)
  local buf = vim.api.nvim_create_buf(false, true)

  local function refresh()
    local out = vim.fn.system({ "tmux", "capture-pane", "-p", "-t", it.pane, "-S", "-60" })
    if vim.v.shell_error ~= 0 then
      vim.notify("Pane " .. it.pane .. " is gone", vim.log.levels.WARN)
      drop(it.pane)
      return false
    end
    local lines = vim.split(out, "\n")
    while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return true
  end

  if not refresh() then return end
  drop(it.pane) -- seen

  local n = bot_num(it.pane)
  local bot = "Claude " .. cfg.bot_names[n]
  local rest = it.name:sub(#bot + 1) -- the " (dir)" suffix

  -- Centered and near-fullscreen: opening a session means you want to focus on it.
  local w = math.floor(vim.o.columns * 0.85)
  local h = math.floor(vim.o.lines * 0.85)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded",
    title = {
      { " " .. icon .. " ", "ClaudeToast" },
      { bot, "ClaudeBot" .. n },
      { rest .. "  [a]nswer [r]efresh [q]uit ", "ClaudeToast" },
    },
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2) - 1,
    col = math.floor((vim.o.columns - w) / 2),
  })
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "FloatBorder:ClaudeToastBorder,FloatTitle:ClaudeToast"
  vim.cmd("normal! G")

  local function map(k, f) vim.keymap.set("n", k, f, { buffer = buf, nowait = true }) end
  map("q", "<cmd>close<cr>")
  map("<Esc>", "<cmd>close<cr>")
  map("r", function() refresh(); vim.cmd("normal! G") end)
  map("a", function()
    -- The cmdline prompt takes its colour from :echohl, so the bot's own
    -- colour marks where you are typing.
    vim.cmd("echohl ClaudeBot" .. n)
    vim.ui.input({ prompt = it.name .. " (N, 1,3 for multi, N text, or text) > " }, function(ans)
      vim.cmd("echohl None")
      if ans == nil then return end -- cancelled
      local ok, err = pcall(answer, it.pane, ans)
      if not ok then vim.notify("Claude inbox: " .. tostring(err), vim.log.levels.ERROR) end
      -- next tab / next question? then stay open, otherwise close
      vim.defer_fn(function()
        if not vim.api.nvim_win_is_valid(win) then return end
        local out = vim.fn.system({ "tmux", "capture-pane", "-p", "-t", it.pane })
        if vim.v.shell_error == 0 and classify(out) == "question" then
          refresh(); vim.cmd("normal! G")
        else
          vim.api.nvim_win_close(win, true)
        end
      end, 700)
    end)
  end)
end

-- Picker ----------------------------------------------------------------------

local ORDER = { question = 1, done = 2, busy = 3, idle = 4 }

local function status_of(p)
  if p.state == "question" then return "question", "has a question", "ClaudeStatusQuestion" end
  if p.state == "busy" then return "busy", "working", "ClaudeStatusBusy" end
  local x = pending(p.pane)
  if x and x.kind == "done" then return "done", "done (unread)", "ClaudeStatusDone" end
  return "idle", "idle", "ClaudeStatusIdle"
end

-- Lists EVERY Claude session, whether or not it has something pending. A
-- custom float rather than vim.ui.select, so the status and bot name can carry
-- their own colours.
function M.pick()
  collect(function(list)
    if #list == 0 then
      return vim.notify("No Claude sessions found in tmux", vim.log.levels.INFO)
    end
    for _, p in ipairs(list) do p.key, p.status, p.hl = status_of(p) end
    table.sort(list, function(a, b)
      if ORDER[a.key] ~= ORDER[b.key] then return ORDER[a.key] < ORDER[b.key] end
      return a.num < b.num
    end)

    local buf = vim.api.nvim_create_buf(false, true)
    local lines, marks, width = {}, {}, 0
    for i, p in ipairs(list) do
      local head = " " .. icon .. " "
      local name = string.format("%-14s", p.name)
      local dir = string.format("  %-24s", p.dir)
      local status = string.format("  %-16s", p.status)
      local line = head .. name .. dir .. status .. "  " .. p.loc
      lines[i] = line
      width = math.max(width, vim.fn.strdisplaywidth(line))
      marks[i] = {
        name = { #head, #head + #name, "ClaudeBot" .. p.num },
        status = { #head + #name + #dir, #head + #name + #dir + #status, p.hl },
      }
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local ns = vim.api.nvim_create_namespace("ClaudeMenu")
    for i, m in ipairs(marks) do
      for _, k in ipairs({ "name", "status" }) do
        vim.api.nvim_buf_add_highlight(buf, ns, m[k][3], i - 1, m[k][1], m[k][2])
      end
    end
    vim.bo[buf].modifiable = false

    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", border = "rounded", style = "minimal",
      title = " " .. icon .. " Claude sessions  [<cr>] open  [1-9] jump  [q] close ",
      width = width + 2, height = #list,
      row = math.floor((vim.o.lines - #list) / 2),
      col = math.floor((vim.o.columns - width - 2) / 2),
    })
    vim.wo[win].cursorline = true
    vim.wo[win].winhighlight = "FloatBorder:ClaudeToastBorder,FloatTitle:ClaudeToast"

    local function choose(i)
      local p = list[i]
      if not p then return end
      vim.api.nvim_win_close(win, true)
      M.open(p)
    end
    local function map(k, f) vim.keymap.set("n", k, f, { buffer = buf, nowait = true }) end
    map("<cr>", function() choose(vim.api.nvim_win_get_cursor(win)[1]) end)
    map("q", "<cmd>close<cr>")
    map("<Esc>", "<cmd>close<cr>")
    for i = 1, math.min(#list, 9) do map(tostring(i), function() choose(i) end) end
  end)
end

-- Shows every pane's tty + detected state, to tune cfg.commands / patterns
function M.debug()
  claude_ttys(function(ttys)
    local out = vim.fn.system({ "tmux", "list-panes", "-a", "-F", PANE_FMT })
    local lines = {}
    for line in out:gmatch("[^\n]+") do
      local id, tty = line:match("^(%S+)\t([^\t]*)")
      local state = ttys[(tty:gsub("^/dev/", ""))] and (M.panes[id] or "?") or "-"
      table.insert(lines, line .. "\t[" .. state .. "]")
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Claude panes" })
  end)
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", cfg, opts or {})
  define_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = define_highlights })
  vim.api.nvim_create_autocmd("VimResized", { callback = layout_toasts })
  if vim.fn.executable("tmux") == 0 then return end
  vim.keymap.set("n", cfg.key, M.pick, { desc = "Claude sessions" })
  vim.api.nvim_create_user_command("ClaudeInboxDebug", M.debug, {})
  M.timer = vim.uv.new_timer()
  M.timer:start(1000, cfg.interval, vim.schedule_wrap(scan))
end

return M
