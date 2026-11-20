-- The Claude session list (<leader>cc, :Claude): a small float with an orange
-- border. Every session with its status (most urgent first), whether it is on
-- screen, its folder and topic; then rows to start one. It redraws live as
-- sessions change state. Plain terminals have their own list (:term).
--
--   <cr> show · n new · R resume · d new in another folder · r rename · x stop
--   (moving around: see config/menu.lua)

local menu = require("config.menu")
local sessions = require("claude.sessions")
local term = require("config.term")

local M = {}

M.FILETYPE = "claudelist" -- listed in hardtime's disabled_filetypes

local ICON = require("claude.toast").ICON
local KEYS = " <cr> show · n new · R resume · d other folder · r rename · x stop · <Esc> close "

local current

local function cwd() return vim.fn.fnamemodify(vim.fn.getcwd(), ":~") end

local function rows()
  local out = {}
  for _, p in ipairs(sessions.list) do
    if term.is_term(p.buf) then out[#out + 1] = { id = p.buf, p = p } end
  end
  out[#out + 1] = { id = "new" }
  out[#out + 1] = { id = "resume" }
  return out
end

local function cols(r, i)
  local p = r.p
  if p then
    local _, label, hl = sessions.status(p)
    return {
      { tostring(i), "ClaudeDim" },
      { ICON, "ClaudePanelTitle" },
      { p.name, "ClaudeBot" .. p.color },
      { label, hl },
      { term.win_of(p.buf) and "on screen" or "hidden", "ClaudeDim" },
      { p.dir or "", "ClaudeDir" },
      { p.topic or "", "ClaudeTopic" },
    }
  end
  local new = r.id == "new"
  return {
    { new and "+" or "↺", new and "ClaudeStatusDone" or "ClaudeStatusBusy" },
    { "" },
    { new and "New session" or "Resume", "ClaudeDir" },
    { "" }, { "" }, { "" },
    { (new and "start Claude in " or "pick an earlier conversation in ") .. cwd(), "ClaudeTopic" },
  }
end

--- actions = { open(p), new(), resume(), new_in_dir(), rename(p, done), stop(p, done) }
--- select = buffer of the session to start on.
function M.open(actions, select)
  local function show(r, m)
    if not r then return end
    m.close()
    if r.p then actions.open(r.p) elseif r.id == "new" then actions.new() else actions.resume() end
  end
  -- Rename / stop ask in the command line and come back to the list.
  local function on_session(fn)
    return function(r, m)
      if not (r and r.p) then return end
      fn(r.p, function() sessions.refresh(function() m.refresh() end) end)
    end
  end

  current = menu.open({
    title = { { " " .. ICON .. " Claude sessions ", "ClaudeToast" } },
    footer = KEYS, footer_hl = "ClaudeDim",
    border_hl = "ClaudeToastBorder", cursor_hl = "ClaudeListCursor",
    filetype = M.FILETYPE, rows = rows, cols = cols, select = select,
    keys = {
      ["<cr>"] = show, o = show, ["<2-LeftMouse>"] = show,
      n = function(_, m) m.close() actions.new() end,
      R = function(_, m) m.close() actions.resume() end,
      d = function(_, m) m.close() actions.new_in_dir() end,
      r = on_session(actions.rename),
      x = on_session(actions.stop),
    },
  })
end

-- Live: states change while the list is up.
sessions.on_scan(function() if current and current.is_open() then current.refresh() end end)

return M
