-- The Claude side panel: docked along the right edge, framed in orange,
-- showing one session at a time. You type straight into Claude there; hiding
-- the panel leaves the session running.
--
--   +-----------+-----------------------------+-╭─ 󰚩 Azure  working ───╮
--   | file tree |  editor                     | │                      │
--   |           |                             | │  (Claude, live)      │
--   |           |                             | ╰──── <Esc><Esc> hide ─╯
--   +-----------+-----------------------------+------------------------+
--
-- A split can't have a border, so the panel is two windows: an empty split
-- that takes the space (the "holder": the editor shrinks to make room, and
-- <C-w> resizing works on it like on any split) and a bordered float sitting
-- exactly on top of it that shows Claude. The float follows the holder.
--
-- Each session is shown through a terminal buffer attached to its tmux pane.
-- The buffer is kept (hidden) when you switch to another session or hide the
-- panel, so coming back is instant; it goes away when the session ends.

local api = vim.api
local tmux = require("claude.tmux")
local sessions = require("claude.sessions")
local alt = require("config.alt")
local resize = require("config.resize")

local M = {}

local ICON = require("claude.toast").ICON
local FOOTER = " <Esc><Esc> hide · ⌥h code · <C-w>←→ resize "

-- holder/float: the two windows; pane: the session shown (or shown last);
-- width: set once you resize the panel by hand, then kept.
local P = { holder = nil, float = nil, pane = nil, last = nil, width = nil, applied = nil }
local views = {} -- pane id -> terminal buffer attached to it
local holder_buf

local function valid(win) return win ~= nil and api.nvim_win_is_valid(win) end

local function default_width()
  local w = P.width or math.floor(vim.o.columns * 0.4)
  return math.max(40, math.min(w, vim.o.columns - 50))
end

--- Size to start a new session at, so it doesn't reflow when first shown.
function M.size()
  return { w = default_width() - 2, h = math.max(10, vim.o.lines - 5) }
end

--- The window Claude is shown in, if the panel is open (in any tabpage).
function M.win() return valid(P.float) and P.float or nil end

--- Open in the current tabpage.
function M.visible()
  return valid(P.holder) and valid(P.float)
    and api.nvim_win_get_tabpage(P.holder) == api.nvim_get_current_tabpage()
end

function M.focused()
  return M.visible() and api.nvim_get_current_win() == P.float
end

--- The session the panel shows, or showed last.
function M.current() return P.pane end

-- Title -----------------------------------------------------------------------

function M.update_title(p)
  local float = M.win()
  p = p or sessions.get(P.pane)
  if not (float and p and p.id == P.pane) then return end
  local _, label, hl = sessions.status(p)
  local title = {
    { " " .. ICON .. " ", "ClaudePanelTitle" },
    { p.name, "ClaudeBot" .. (p.color or 1) },
    { "  " .. label, hl },
    { "  " .. (p.dir or ""), "ClaudePanelFooter" },
  }
  local used = 0
  for _, c in ipairs(title) do used = used + vim.fn.strdisplaywidth(c[1]) end
  local room = api.nvim_win_get_width(float) - used - 4
  if p.topic and room > 8 then
    local topic = p.topic
    if vim.fn.strdisplaywidth(topic) > room then
      topic = vim.fn.strcharpart(topic, 0, room - 1) .. "…"
    end
    title[#title + 1] = { " · " .. topic, "ClaudeTopic" }
  end
  title[#title + 1] = { " ", "ClaudePanelTitle" }
  api.nvim_win_set_config(float, { title = title, title_pos = "left" })
end

-- Windows ---------------------------------------------------------------------

local function plain_opts(win)
  local wo = vim.wo[win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.spell = false
  wo.list = false
  wo.cursorline = false
  wo.colorcolumn = ""
  wo.wrap = false
end

--- The float covers the holder's text and statusline, and the separator on its
--- left, so the border is the only line between the code and Claude.
local function geometry()
  local left = api.nvim_win_get_position(P.holder)[2] > 0 and 1 or 0
  local stl = vim.o.laststatus == 3 and 0 or 1
  return {
    relative = "win", win = P.holder, row = 0, col = -left,
    width = math.max(1, api.nvim_win_get_width(P.holder) + left - 2),
    height = math.max(1, api.nvim_win_get_height(P.holder) + stl - 2),
  }
end

local function sync()
  if not (valid(P.holder) and valid(P.float)) then return end
  api.nvim_win_set_config(P.float, geometry())
  M.update_title()
end

--- Close a window without taking Neovim down with it when it is the last one.
local function close_win(win)
  if not valid(win) then return end
  vim.wo[win].winfixbuf = false
  local tab = api.nvim_win_get_tabpage(win)
  local others = 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if w ~= win and api.nvim_win_get_config(w).relative == "" then others = others + 1 end
  end
  if others == 0 and #api.nvim_list_tabpages() == 1 then
    -- An empty buffer instead; config/layout.lua then rebuilds around it.
    api.nvim_win_call(win, function()
      vim.cmd("enew")
      vim.cmd("setlocal winfixwidth< statusline< number< relativenumber< signcolumn<")
    end)
    return
  end
  pcall(api.nvim_win_close, win, true)
end

--- The empty buffer of the holder split. Entering it means entering the panel.
local function get_holder_buf()
  if holder_buf and api.nvim_buf_is_valid(holder_buf) then return holder_buf end
  holder_buf = api.nvim_create_buf(false, true)
  vim.bo[holder_buf].bufhidden = "hide"
  -- Also tells lualine to leave its statusline alone (plugins/lualine.lua).
  vim.bo[holder_buf].filetype = "claudepanel"
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    buffer = holder_buf,
    callback = function()
      -- Coming out of the panel (<C-w>p and the like), carry on to the code;
      -- coming from anywhere else, go into the panel.
      local from_panel = vim.fn.win_getid(vim.fn.winnr("#")) == P.float
      vim.schedule(function()
        if api.nvim_get_current_buf() ~= holder_buf or not valid(P.float) then return end
        local left = vim.fn.win_getid(vim.fn.winnr("h"))
        if from_panel and left ~= 0 and left ~= api.nvim_get_current_win() then
          api.nvim_set_current_win(left)
        else
          api.nvim_set_current_win(P.float)
          vim.cmd("startinsert")
        end
      end)
    end,
  })
  return holder_buf
end

function M.hide()
  local holder, float = P.holder, P.float
  P.holder, P.float = nil, nil
  if valid(holder) then
    local width = api.nvim_win_get_width(holder)
    if P.applied and width ~= P.applied then P.width = width end -- resized by hand
  end
  if valid(float) then
    if api.nvim_get_current_win() == float then vim.cmd("stopinsert") end
    vim.wo[float].winfixbuf = false
    pcall(api.nvim_win_close, float, true)
  end
  close_win(holder)
end

local function set_buf(win, buf)
  vim.wo[win].winfixbuf = false
  api.nvim_win_set_buf(win, buf)
  -- Nothing else lands in here: :e, gd or <S-l> from the panel would hide
  -- Claude behind a file. Telescope and the tree already avoid it.
  vim.wo[win].winfixbuf = true
end

--- Both windows in this tabpage, created if needed, with `buf` in the float.
local function ensure(buf)
  if valid(P.holder) and api.nvim_win_get_tabpage(P.holder) ~= api.nvim_get_current_tabpage() then
    M.hide()
  end
  if not valid(P.holder) then
    local stale = P.float
    P.float = nil -- before closing, so WinClosed doesn't take the new panel down
    if valid(stale) then pcall(api.nvim_win_close, stale, true) end
    local width = default_width()
    P.holder = api.nvim_open_win(get_holder_buf(), false, { split = "right", win = -1, width = width })
    P.applied = width
    plain_opts(P.holder)
    vim.wo[P.holder].winfixwidth = true
    vim.wo[P.holder].winfixbuf = true
    vim.wo[P.holder].statusline = " "
    vim.wo[P.holder].fillchars = "eob: "
  end
  if not valid(P.float) then
    P.float = api.nvim_open_win(buf, false, vim.tbl_extend("force", geometry(), {
      border = "rounded", zindex = 20, focusable = true,
      title = { { " " .. ICON .. " ", "ClaudePanelTitle" } }, title_pos = "left",
      footer = { { FOOTER, "ClaudePanelFooter" } }, footer_pos = "right",
    }))
    vim.wo[P.float].winhighlight = table.concat({
      "NormalFloat:Normal", "FloatBorder:ClaudePanelBorder",
      "FloatTitle:ClaudePanelTitle", "FloatFooter:ClaudePanelFooter",
    }, ",")
    vim.wo[P.float].winfixbuf = true
  else
    set_buf(P.float, buf)
  end
  plain_opts(P.float)
  sync()
  return P.float
end

-- Terminal views ----------------------------------------------------------------

local function forget(pane, buf)
  if views[pane] == buf then views[pane] = nil end
  if valid(P.float) and api.nvim_win_get_buf(P.float) == buf then
    M.hide()
    if P.pane == pane then P.pane, P.last = nil, nil end
  end
  if api.nvim_buf_is_valid(buf) then pcall(api.nvim_buf_delete, buf, { force = true }) end
end

--- Leave the panel for the window next to it. Neovim's own <C-w>h/j/k/l jump
--- from a float to the previous window whichever key you press -- after
--- coming in through the holder that is the holder, which sends you straight
--- back. So look from where the panel sits instead.
function M.go(dir)
  if not valid(P.holder) then return end
  local target = api.nvim_win_call(P.holder, function() return vim.fn.win_getid(vim.fn.winnr(dir)) end)
  if target == 0 or target == P.holder then return end
  if api.nvim_get_mode().mode == "t" then vim.cmd("stopinsert") end
  api.nvim_set_current_win(target)
end

local function keymaps(buf)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, nowait = true, desc = "Claude: " .. desc })
  end
  -- A single <Esc> and every other key go to Claude.
  map("t", "<Esc><Esc>", M.hide, "hide panel (keeps running)")
  map({ "t", "n" }, "<C-q>", M.hide, "hide panel (keeps running)")
  map("n", "q", M.hide, "hide panel (keeps running)")
  -- <C-w>hjkl and Alt+hjkl (or what macOS turns those into) go to the window
  -- next door.
  for dir, keys in pairs(alt.keys) do
    for _, lhs in ipairs(vim.list_extend({ "<C-w>" .. dir }, keys)) do
      map({ "t", "n" }, lhs, function() M.go(dir) end, "go to the window " .. alt.names[dir])
    end
  end
  -- <C-w> + arrows resize the panel, from typing or from normal mode.
  for key in pairs(resize.ARROW_DIRS) do
    map({ "t", "n" }, "<C-w>" .. key, function()
      if valid(P.holder) then resize.loop(key, P.holder) end
    end, "resize the panel (arrows, <Esc> stops)")
  end
end

local function start(p, buf, win)
  views[p.id] = buf
  api.nvim_win_call(win, function()
    vim.fn.jobstart(tmux.attach_cmd(p), {
      term = true,
      on_exit = function() vim.schedule(function() forget(p.id, buf); sessions.refresh() end) end,
    })
  end)
  vim.bo[buf].bufhidden = "hide"
  keymaps(buf)
  -- Back in the panel means back to typing; looking counts as reading it.
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    buffer = buf,
    callback = function()
      sessions.mark_seen(p.id)
      vim.schedule(function()
        if api.nvim_get_current_buf() == buf and api.nvim_get_mode().mode ~= "t" then
          vim.cmd("startinsert")
        end
      end)
    end,
  })
end

--- Show session `p` in the panel (opening the panel if needed).
--- opts.focus = false leaves the cursor where it is.
function M.show(p, opts)
  opts = opts or {}
  if not tmux.pane_alive(p.id) then
    vim.notify("Claude " .. p.name .. " is gone", vim.log.levels.WARN)
    if views[p.id] then forget(p.id, views[p.id]) end
    sessions.refresh()
    return
  end

  local buf = views[p.id]
  local fresh = not (buf and api.nvim_buf_is_valid(buf))
  if fresh then buf = api.nvim_create_buf(false, true) end
  local win = ensure(buf)
  if fresh then start(p, buf, win) end

  P.pane, P.last = p.id, p
  sessions.mark_seen(p.id)
  M.update_title(p)
  if opts.focus ~= false then
    api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end
end

--- Show the panel's session again (after config/layout.lua rebuilt the screen).
function M.reopen(opts)
  local p = P.pane and (sessions.get(P.pane) or (P.last and P.last.id == P.pane and P.last))
  if p then M.show(p, opts) end
end

--- Drop the view of a session that is being stopped.
function M.close_view(pane)
  if views[pane] then forget(pane, views[pane]) end
end

-- Keeping the two windows together ---------------------------------------------

local group = api.nvim_create_augroup("ClaudePanel", { clear = true })

api.nvim_create_autocmd("WinResized", { group = group, callback = sync })
-- Every step of <C-w> + arrows (config/resize.lua), not just the end of it.
api.nvim_create_autocmd("User", { group = group, pattern = "ViewNudged", callback = sync })

-- Keep the default width proportional to the screen until you pick your own.
api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    if valid(P.holder) and not P.width then
      local width = default_width()
      api.nvim_win_set_width(P.holder, width)
      P.applied = width
    end
    sync()
  end,
})

-- Either half closed some other way (:q in the float, <C-w>o in the editor):
-- take the other half with it.
api.nvim_create_autocmd("WinClosed", {
  group = group,
  callback = function(ev)
    local closed = tonumber(ev.match)
    if closed and (closed == P.holder or closed == P.float) then
      if closed == P.holder then P.holder = nil else P.float = nil end
      vim.schedule(M.hide)
    end
  end,
})

-- A session's status changes while you look at it: keep its title current.
sessions.on_scan(function() M.update_title() end)

return M
