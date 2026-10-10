-- Watches tmux panes running Claude Code and notifies you in Neovim when one
-- has a question or finishes. Needs nothing on Claude's side (no hooks,
-- no settings.json), so it works no matter how Claude is sandboxed.
-- Requires Neovim 0.10+ and Claude running in a pane of the same tmux server.
--
--   <leader>cc   list every Claude session with its status, open one: it
--   attaches in a float and you type into Claude directly. <C-q> closes it
--   (the session keeps running). <leader>cc then d restarts the chosen
--   session in another directory.

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
      local found, seen = {}, {}
      for line in r.stdout:gmatch("[^\n]+") do
        local id, tty, path, loc = line:match("^(%S+)\t([^\t]*)\t([^\t]*)\t(.*)$")
        -- a popup's grouped session lists the same pane a second time
        if id and not seen[id] and ttys[(tty:gsub("^/dev/", ""))] then
          seen[id] = true
          local n = bot_num(id)
          found[#found + 1] = {
            pane = id, num = n, name = "Claude " .. cfg.bot_names[n],
            dir = vim.fn.fnamemodify(path, ":t"), path = path, loc = loc,
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

-- Opening ---------------------------------------------------------------------

-- Attaches to the pane's tmux session in a float, so you type straight into
-- Claude. The float uses a throwaway grouped session (own current window, shares
-- the real one's windows) with the prefix key and status bar off, so tmux is
-- invisible, and destroy-unattached removes it when the float closes.
function M.open(it)
  local target = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", it.pane, "#{session_name}" }))
  if vim.v.shell_error ~= 0 or target == "" then
    vim.notify("Pane " .. it.pane .. " is gone", vim.log.levels.WARN)
    drop(it.pane)
    return
  end
  drop(it.pane) -- seen

  local n = bot_num(it.pane)
  local bot = "Claude " .. cfg.bot_names[n]
  local rest = it.name:sub(#bot + 1) -- the " (dir)" suffix
  local grp = "claude-popup-" .. it.pane:gsub("%%", "") .. "-" .. vim.uv.hrtime() % 100000

  local buf = vim.api.nvim_create_buf(false, true)
  -- Centered and near-fullscreen: opening a session means you want to focus on it.
  local w = math.floor(vim.o.columns * 0.85)
  local h = math.floor(vim.o.lines * 0.85)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded",
    title = {
      { " " .. icon .. " ", "ClaudeToast" },
      { bot, "ClaudeBot" .. n },
      { rest .. "  [<Esc><Esc>] close ", "ClaudeToast" },
    },
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2) - 1,
    col = math.floor((vim.o.columns - w) / 2),
  })
  vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:ClaudeToastBorder,FloatTitle:ClaudeToast"

  local cmd = {
    "tmux", "new-session", "-t", target, "-s", grp,
    ";", "set-option", "-t", grp, "prefix", "None",
    ";", "set-option", "-t", grp, "status", "off",
    ";", "set-option", "-t", grp, "destroy-unattached", "on",
    ";", "select-window", "-t", it.pane,
    ";", "select-pane", "-t", it.pane,
  }
  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart(cmd, { term = true })
  else
    vim.fn.termopen(cmd)
  end
  vim.bo[buf].bufhidden = "wipe"

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  -- A single Esc and everything else go to Claude; <Esc><Esc> or <C-q> leaves.
  vim.keymap.set("t", "<C-q>", close, { buffer = buf, desc = "Close Claude popup" })
  -- Overrides the global <Esc><Esc> (exit terminal mode) inside this float.
  vim.keymap.set("t", "<Esc><Esc>", close, { buffer = buf, desc = "Close Claude popup" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd("TermClose", { buffer = buf, once = true, callback = function()
    vim.schedule(close) -- Claude / the session ended
  end })
  vim.cmd("startinsert")
end

-- Changing directory ------------------------------------------------------------

-- A running process can't change its working directory from outside, and
-- Claude Code has no command for it. So: /exit, wait for the shell underneath
-- (see tmux-start.sh), then `cd <dir> && claude`. The conversation is lost:
-- Claude keeps its history per directory.
function M.chdir(p, dir)
  dir = vim.fn.fnamemodify(vim.fn.expand(dir), ":p")
  if vim.fn.isdirectory(dir) == 0 then
    return vim.notify("Not a directory: " .. dir, vim.log.levels.ERROR)
  end
  local tty = vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", p.pane, "#{pane_tty}" }))
  if vim.v.shell_error ~= 0 then return vim.notify("Pane " .. p.pane .. " is gone", vim.log.levels.WARN) end
  tty = tty:gsub("^/dev/", "")
  -- A pane left in copy-mode (scrolled, mouse wheel) turns send-keys into
  -- copy-mode bindings: "f" is "jump forward", "/" is search. Leave it first.
  vim.system({ "tmux", "copy-mode", "-q", "-t", p.pane }):wait()
  vim.system({ "tmux", "send-keys", "-t", p.pane, "-l", "/exit" }):wait()
  vim.system({ "tmux", "send-keys", "-t", p.pane, "Enter" }):wait()
  local tries = 0
  local function wait()
    tries = tries + 1
    claude_ttys(function(ttys)
      if ttys[tty] then
        if tries > 40 then
          return vim.notify(p.name .. " did not exit; directory not changed", vim.log.levels.WARN)
        end
        return vim.defer_fn(wait, 250)
      end
      vim.system({ "tmux", "copy-mode", "-q", "-t", p.pane }):wait()
      vim.system({ "tmux", "send-keys", "-t", p.pane, "cd " .. vim.fn.shellescape(dir) .. " && claude", "Enter" })
      drop(p.pane)
      M.panes[p.pane] = nil
      vim.notify(p.name .. " restarted in " .. dir, vim.log.levels.INFO)
    end)
  end
  vim.defer_fn(wait, 400)
end

local function ask_chdir(p)
  if p.state ~= "idle" then
    return vim.notify(p.name .. " is busy or has a question; wait until it is idle", vim.log.levels.WARN)
  end
  vim.cmd("echohl ClaudeBot" .. p.num)
  vim.ui.input({
    prompt = p.name .. " restarts in (conversation is lost) > ",
    default = p.path, completion = "dir",
  }, function(dir)
    vim.cmd("echohl None")
    if dir and dir ~= "" then M.chdir(p, dir) end
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
      title = " " .. icon .. " Claude sessions  [<cr>] open  [1-9] jump  [d] change dir  [q] close ",
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
    map("d", function()
      local p = list[vim.api.nvim_win_get_cursor(win)[1]]
      vim.api.nvim_win_close(win, true)
      if p then ask_chdir(p) end
    end)
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
