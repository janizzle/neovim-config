-- Claude Code inside Neovim.
--
-- Start sessions on demand, as many as you like, and work with them in a side
-- panel on the right. Every session runs in tmux (a hidden session of its own),
-- so it keeps running when you hide the panel or quit Neovim, and every Neovim
-- on the machine sees the same ones. A Claude you started by hand in any tmux
-- pane shows up too.
--
-- You get a toast when a session has a question or finishes, and the
-- statusline counts what is waiting for you.
--
--   <leader>cc  sessions: pick one, new, resume, rename, stop (also <leader>al)
--   <leader>aa  toggle the panel   <leader>an  new   <leader>ar  rename
--   In the panel: type into Claude. <Esc><Esc> (or <C-q>) hides it, ⌥h goes
--   back to the code, <C-w> + arrows resize it.
--
-- Commands: :Claude (toggle) :ClaudeOpen [name] :ClaudeClose :ClaudeNew [name]
--           :ClaudeResume :ClaudeList :ClaudeRename [name] :ClaudeDebug

local tmux = require("claude.tmux")
local sessions = require("claude.sessions")
local panel = require("claude.panel")
local picker = require("claude.picker")
local toast = require("claude.toast")

local M = {}

local cfg = {
  interval = 2000, -- ms between scans
  toast_ms = { question = 10000, done = 6000 },
}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.WARN, { title = "Claude" })
end

local function define_highlights()
  local C = require("config.palette")
  local set = function(n, o) vim.api.nvim_set_hl(0, n, o) end
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
  set("ClaudePanelBorder", { fg = C.claude })
  set("ClaudePanelTitle", { fg = C.claude, bold = true })
  set("ClaudePanelFooter", { fg = C.line_nr })
  set("ClaudeListCursor", { bg = C.bg_sel })
  for i, c in ipairs(sessions.COLORS) do
    set("ClaudeBot" .. i, { fg = c, bold = true })
  end
end

local function claude_bin()
  if not tmux.available() then return notify("Claude sessions need tmux") end
  local bin = vim.fn.exepath("claude")
  if bin == "" then return notify("`claude` is not on your PATH") end
  return bin
end

local function slug(s)
  s = s:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s ~= "" and s or "session"
end

-- Actions ---------------------------------------------------------------------

--- Start a session in the cwd and show it. Asks for a name (Enter takes the
--- suggested one) unless opts.name is given; opts.args go to `claude`.
function M.new(opts)
  opts = opts or {}
  local bin = claude_bin()
  if not bin then return end

  local function start(name)
    name = vim.trim(name or "")
    if name == "" then return end
    if sessions.find(name) then return notify("There already is a session called " .. name) end

    local dir = opts.dir or vim.fn.getcwd()
    local base = "claude-" .. slug(name)
    local sname, i = base, 2
    while tmux.has_session(sname) do sname, i = base .. "-" .. i, i + 1 end

    local color = sessions.free_color()
    local cmd = vim.fn.shellescape(bin) .. (opts.args and (" " .. opts.args) or "")
    local pane, window = tmux.new_session(sname, dir, cmd, panel.size(),
      { claude_name = name, claude_color = color, claude_owned = 1 })
    if not pane then return notify("Could not start Claude: " .. (window or "?"), vim.log.levels.ERROR) end

    panel.show({
      id = pane, session = sname, window = window, loc = sname .. ":" .. window,
      name = name, color = color, owned = true, path = dir,
      dir = vim.fn.fnamemodify(dir, ":t"), state = "idle",
    })
    sessions.refresh()
  end

  if opts.name then return start(opts.name) end
  vim.ui.input({ prompt = "New Claude session, name: ", default = sessions.free_name() }, start)
end

function M.rename(p, done)
  vim.ui.input({ prompt = "Rename " .. p.name .. " to: ", default = p.name }, function(name)
    name = vim.trim(name or "")
    local other = name ~= "" and sessions.find(name)
    if other and other.id ~= p.id then
      notify("There already is a session called " .. name)
    elseif name ~= "" and name ~= p.name then
      sessions.rename(p, name)
      panel.update_title(p)
    end
    if done then done() end
  end)
end

--- Restart in another directory. A running process can't change directory
--- from outside, so Claude is replaced by a new one there; the conversation
--- ends (Claude keeps history per directory, :ClaudeResume finds it again).
function M.chdir(p)
  local bin = claude_bin()
  if not bin then return end
  if p.state ~= "idle" and vim.fn.confirm(p.name .. " is " .. (p.state == "busy" and "working" or "asking something")
      .. ". Restart it anyway?", "&Restart\n&Cancel", 2) ~= 1 then
    return
  end
  vim.ui.input({
    prompt = p.name .. " restarts in (conversation ends): ", default = p.path, completion = "dir",
  }, function(dir)
    if not dir or vim.trim(dir) == "" then return end
    dir = vim.fn.fnamemodify(vim.fn.expand(vim.trim(dir)), ":p")
    if vim.fn.isdirectory(dir) == 0 then return notify("Not a directory: " .. dir, vim.log.levels.ERROR) end
    local cmd = vim.fn.shellescape(bin)
    -- A pane you made yourself goes back to a shell when Claude exits.
    if not p.owned then cmd = cmd .. '; exec "${SHELL:-/bin/sh}"' end
    local ok, _, err = tmux.respawn(p.id, dir, cmd)
    if not ok then return notify("Restart failed: " .. err, vim.log.levels.ERROR) end
    notify(p.name .. " restarted in " .. vim.fn.fnamemodify(dir, ":~"), vim.log.levels.INFO)
    sessions.refresh()
  end)
end

function M.stop(p, done)
  local what = p.owned and "" or " (its tmux pane goes back to a shell)"
  if vim.fn.confirm("Stop Claude " .. p.name .. what .. "?", "&Stop\n&Cancel", 2) == 1 then
    panel.close_view(p.id)
    if p.owned then
      tmux.kill_pane(p.id)
    else
      tmux.respawn(p.id, p.path, 'exec "${SHELL:-/bin/sh}"')
    end
  end
  if done then done() else sessions.refresh() end
end

--- Show `p` (a session or its name) in the panel. Without one: the session
--- the panel showed last, the only one there is, or a choice -- or a new one
--- when there are none.
function M.open(p)
  if type(p) == "string" then
    local found = sessions.find(p)
    if not found then return notify("No Claude session called " .. p) end
    p = found
  end
  if p then return panel.show(p) end

  local last = panel.current() and sessions.get(panel.current())
  if last then return panel.show(last) end
  sessions.refresh(function(list)
    if #list == 0 then return M.new() end
    if #list == 1 then return panel.show(list[1]) end
    M.list()
  end)
end

function M.close() panel.hide() end

function M.toggle()
  if panel.visible() then M.close() else M.open() end
end

local actions = {
  open = function(p) panel.show(p) end,
  new = function() M.new() end,
  resume = function() M.new({ args = "--resume" }) end,
  rename = function(p, done) M.rename(p, done) end,
  chdir = function(p) M.chdir(p) end,
  stop = function(p, done) M.stop(p, done) end,
}

function M.list()
  local function show() picker.open(actions, { select = panel.current() }) end
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
  if panel.focused() and panel.current() == p.id then
    sessions.mark_seen(p.id)
    return
  end
  local chunks = {
    { p.name, "ClaudeBot" .. p.color },
    { kind == "question" and " has a question" or " is done" },
    { "  " .. (p.topic or p.dir or ""), "ClaudeToastDim" },
  }
  toast.show(chunks, cfg.toast_ms[kind])
end

local function complete_names(lead)
  local out = {}
  for _, p in ipairs(sessions.list) do
    if p.name:lower():find(lead:lower(), 1, true) == 1 then out[#out + 1] = p.name end
  end
  return out
end

function M.setup(opts)
  cfg = vim.tbl_deep_extend("force", cfg, opts or {})
  define_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = define_highlights })
  vim.api.nvim_create_autocmd("VimResized", { callback = toast.layout })

  sessions.on_scan(function(_, events)
    for _, e in ipairs(events) do alert(e[1], e[2]) end
  end)

  local map = function(lhs, fn, desc) vim.keymap.set("n", lhs, fn, { desc = "Claude: " .. desc }) end
  map("<leader>cc", M.list, "sessions (pick, new, rename, stop)")
  map("<leader>al", M.list, "sessions (pick, new, rename, stop)")
  map("<leader>aa", M.toggle, "toggle side panel")
  map("<leader>an", function() M.new() end, "new session")
  map("<leader>ar", function()
    local p = panel.current() and sessions.get(panel.current())
    if p then M.rename(p) else M.list() end
  end, "rename session")

  local cmd = vim.api.nvim_create_user_command
  cmd("Claude", M.toggle, { desc = "Toggle the Claude panel" })
  cmd("ClaudeOpen", function(o) M.open(o.args ~= "" and o.args or nil) end,
    { nargs = "?", complete = complete_names, desc = "Show a Claude session in the panel" })
  cmd("ClaudeClose", M.close, { desc = "Hide the Claude panel (sessions keep running)" })
  cmd("ClaudeNew", function(o) M.new({ name = o.args ~= "" and o.args or nil }) end,
    { nargs = "?", desc = "Start a Claude session in the cwd" })
  cmd("ClaudeResume", function() M.new({ args = "--resume" }) end,
    { desc = "Start a Claude session that picks up an earlier conversation" })
  cmd("ClaudeList", M.list, { desc = "List Claude sessions" })
  cmd("ClaudeRename", function(o)
    local p = panel.current() and sessions.get(panel.current())
    if not p then return notify("No session in the panel; rename from :ClaudeList") end
    if o.args ~= "" then
      local other = sessions.find(o.args)
      if other and other.id ~= p.id then return notify("There already is a session called " .. o.args) end
      sessions.rename(p, o.args)
      panel.update_title(p)
    else
      M.rename(p)
    end
  end, { nargs = "?", desc = "Rename the session in the panel" })
  cmd("ClaudeDebug", sessions.debug, { desc = "Show every tmux pane and its Claude state" })

  if tmux.available() then sessions.start(cfg.interval) end
end

return M
