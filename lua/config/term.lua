-- Terminals. Every terminal -- a shell, a Claude session, a devflow run -- is
-- an ordinary :term buffer in an ordinary split, so it takes part in window
-- management like any other window, and its normal mode is a real buffer:
-- motions, search, visual mode and yank all work on the whole scrollback.
--
-- Closing a terminal's window never stops it (Neovim only hides the buffer);
-- <C-q> does that from anywhere, and brings it back where it was.
--
--   In a terminal  <Esc>        normal mode: move, /search, v, y like a buffer
--                  i  a         back to typing
--                  <C-\><Esc>   send a real Esc to the program
--                  <C-q>        hide (keeps running)
--                  <C-w>hjkl ⌥hjkl   next window     <C-w>← →   resize
--                  <C-w>s  <C-w>v    split: a new shell there, not a mirror
--   Elsewhere      <C-q>        the last hidden terminal back (none: new shell)
--   :term  <leader>tt           the terminal list (config/termlist.lua)
--   :term {cmd}                 run cmd in a full-width row along the bottom
-- Claude sessions are terminals too, but have their own list (<leader>cc).
--
-- A terminal remembers where it lives -- "bottom" (a full-width row) or
-- "right" (a full-height column) -- and its size, so it comes back in place.

local api = vim.api

local M = {}

local recent = {}        -- terminal buffers, most recently used first
local wb_groups = {}     -- winbar highlight groups made so far (see hl())
M.title_providers = {}   -- fn(buf) -> chunks | nil; claude/ labels its sessions
M.owners = {}            -- fn(buf) -> true for terminals another list shows (claude/)

-- Queries ---------------------------------------------------------------------

function M.is_term(buf)
  return buf ~= nil and api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal"
end

function M.job(buf)
  local ok, job = pcall(function() return vim.b[buf].terminal_job_id end)
  return ok and job or nil
end

function M.running(buf)
  local job = M.is_term(buf) and M.job(buf)
  return job ~= nil and job ~= false and vim.fn.jobwait({ job }, 0)[1] == -1
end

--- Every terminal buffer, oldest first.
function M.list()
  local out = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if M.is_term(buf) then out[#out + 1] = buf end
  end
  return out
end

--- The window showing `buf` in the current tabpage, if any.
function M.win_of(buf)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(win) == buf and api.nvim_win_get_config(win).relative == "" then
      return win
    end
  end
end

--- Listed elsewhere (a Claude session), so not in the terminal list.
function M.owned(buf)
  for _, fn in ipairs(M.owners) do
    local ok, res = pcall(fn, buf)
    if ok and res then return true end
  end
  return false
end

--- Terminal buffers on screen in any tabpage.
function M.visible()
  local out, seen = {}, {}
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if M.is_term(buf) and not seen[buf] and api.nvim_win_get_config(win).relative == "" then
      seen[buf] = true
      out[#out + 1] = buf
    end
  end
  return out
end

--- Name shown in the winbar and the terminal list.
function M.name(buf)
  local name = vim.b[buf].term_name
  if name and name ~= "" then return name end
  local first = vim.split(vim.b[buf].term_cmd or "", " ", { plain = true, trimempty = true })[1]
  return first and vim.fs.basename(first) or "terminal"
end

--- The title the program set (a shell: user@host:dir), or "" -- not Neovim's
--- own term://... buffer name, which is what it reports when there is none.
function M.title(buf)
  local t = vim.b[buf].term_title or ""
  return t:match("^term://") and "" or t
end

local function touch(buf)
  for i, b in ipairs(recent) do
    if b == buf then table.remove(recent, i) break end
  end
  table.insert(recent, 1, buf)
end

-- Winbar ------------------------------------------------------------------------

--- Winbar copies of a highlight group, on the winbar's background, so a
--- chunk's own colour never drops back to Normal's background mid-row.
local function hl(group)
  local name = "TermWinbar_" .. group
  if not wb_groups[name] then
    local src = api.nvim_get_hl(0, { name = group, link = false })
    api.nvim_set_hl(0, name, {
      fg = src.fg, bold = src.bold, italic = src.italic,
      bg = require("config.palette").bg_alt,
    })
    wb_groups[name] = true
  end
  return "%#" .. name .. "#"
end

local function define_highlights()
  wb_groups = {}
  local C = require("config.palette")
  api.nvim_set_hl(0, "TermTitle", { fg = C.blue, bold = true })
  api.nvim_set_hl(0, "TermDim", { fg = C.unused, italic = true })
  api.nvim_set_hl(0, "TermHint", { fg = C.line_nr })
end

local HINT = "<Esc> normal · i type · <C-q> hide "

--- Winbar of the window being drawn (the 'winbar' expression below).
function M.winbar()
  local win = vim.g.statusline_winid or api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if not M.is_term(buf) then return "" end

  local chunks
  for _, provider in ipairs(M.title_providers) do
    local ok, res = pcall(provider, buf)
    if ok and res then chunks = res break end
  end
  if not chunks then
    local title = M.title(buf)
    chunks = {
      { "  " .. M.name(buf), "TermTitle" },
      { M.running(buf) and "" or "  exited", "DiagnosticError" },
      { title ~= "" and ("  " .. title) or "", "TermDim" },
    }
  end

  local out, used = {}, 1
  for i, c in ipairs(chunks) do
    if c[1] ~= "" then
      out[#out + 1] = hl(c[2]) .. (c[1]:gsub("%%", "%%%%"))
      used = used + vim.fn.strdisplaywidth(c[1])
    end
    -- A narrow window cuts the descriptive tail, never the name.
    if i == 2 then out[#out + 1] = "%<" end
  end
  -- The key hint only where it fits beside the title, never on top of it.
  local tail = hl("TermHint") .. "%="
  if used + vim.fn.strdisplaywidth(HINT) + 2 <= api.nvim_win_get_width(win) then tail = tail .. HINT end
  return " " .. table.concat(out) .. tail
end

local WINBAR = "%{%v:lua.require'config.term'.winbar()%}"

--- Window options for a window showing a terminal. Called whenever a terminal
--- lands in a window, and the window gets them back once it shows a file.
local function style(win, buf)
  if not api.nvim_win_is_valid(win) or api.nvim_win_get_config(win).relative ~= "" then return end
  if M.is_term(buf) then
    vim.wo[win].winbar = WINBAR
    vim.wo[win].signcolumn = "no"
    vim.wo[win].colorcolumn = ""
    vim.wo[win].spell = false
    vim.w[win].term_styled = true
  elseif vim.w[win].term_styled then
    vim.w[win].term_styled = nil
    api.nvim_win_call(win, function() vim.cmd("setlocal winbar< signcolumn< colorcolumn< spell<") end)
  end
end

-- Placing -------------------------------------------------------------------------

local function default_size(home)
  if home == "right" then
    return math.max(40, math.min(math.floor(vim.o.columns * 0.4), vim.o.columns - 50))
  end
  return 15
end

--- Where a terminal nobody placed for us lives: a column if it runs (nearly)
--- the full height and not the full width, else a row.
local function infer_home(win)
  local full_h = vim.o.lines - vim.o.cmdheight - 3
  return (api.nvim_win_get_width(win) < vim.o.columns - 1 and api.nvim_win_get_height(win) >= full_h)
    and "right" or "bottom"
end

local function remember(win, buf)
  if not (api.nvim_win_is_valid(win) and M.is_term(buf)) then return end
  local home = vim.b[buf].term_home or infer_home(win)
  vim.b[buf].term_home = home
  vim.b[buf].term_size = home == "right" and api.nvim_win_get_width(win) or api.nvim_win_get_height(win)
end

--- A window for `buf` at its home; returns it, without focusing it.
local function place(buf)
  local home = vim.b[buf].term_home or "bottom"
  local size = vim.b[buf].term_size or default_size(home)
  local win = api.nvim_open_win(buf, false, home == "right"
    and { split = "right", win = -1, width = size }
    or { split = "below", win = -1, height = size })
  vim.wo[win].winfixwidth = home == "right"
  vim.wo[win].number = vim.go.number
  vim.wo[win].relativenumber = vim.go.relativenumber
  style(win, buf)
  return win
end

--- Show `buf` (in place if it is on screen already) and, unless opts.focus is
--- false, go into it -- typing again, unless you left it in normal mode.
function M.show(buf, opts)
  opts = opts or {}
  if not M.is_term(buf) then return end
  local win = M.win_of(buf) or place(buf)
  touch(buf)
  if opts.focus ~= false then
    api.nvim_set_current_win(win)
    if vim.b[buf].term_typing ~= false and M.running(buf) then vim.cmd("startinsert") end
  end
  return win
end

--- A buffer to put in a window that must not close: the alternate file, else
--- any listed file, else a new empty one.
local function fallback_buffer(not_this)
  local alt = vim.fn.bufnr("#")
  if alt > 0 and alt ~= not_this and vim.bo[alt].buflisted and vim.bo[alt].buftype == "" then return alt end
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= not_this and vim.bo[b].buflisted and vim.bo[b].buftype == "" then return b end
  end
  return api.nvim_create_buf(true, false)
end

--- Hide the terminal in `win` (default: the current window). It keeps running.
function M.hide(win)
  win = win or api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  if not M.is_term(buf) then return end
  remember(win, buf)
  touch(buf)
  local current = api.nvim_get_current_win() == win
  -- Back to the window you came from, or the code -- never the file tree,
  -- which is where Neovim itself would often drop you.
  local back = current and vim.fn.win_getid(vim.fn.winnr("#")) or 0
  if current and api.nvim_get_mode().mode == "t" then pcall(vim.cmd, "stopinsert") end
  local others = 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win))) do
    if w ~= win and api.nvim_win_get_config(w).relative == "" then others = others + 1 end
  end
  -- The only window left: closing it would close Neovim, so swap a file in.
  if others == 0 or not pcall(api.nvim_win_close, win, false) then
    api.nvim_win_set_buf(win, fallback_buffer(buf))
    return
  end
  if not current then return end
  if back ~= 0 and api.nvim_win_is_valid(back) and api.nvim_win_get_config(back).relative == ""
    and vim.bo[api.nvim_win_get_buf(back)].filetype ~= "NvimTree"
  then
    api.nvim_set_current_win(back)
  else
    local main = require("config.windows").find_main_window()
    if main then api.nvim_set_current_win(main) end
  end
end

--- <C-q>: hide the terminal you are in; anywhere else, bring back the terminal
--- you used last that is not on screen (or jump into one that is, or start a
--- shell when there are none).
function M.toggle()
  local cur = api.nvim_get_current_buf()
  if M.is_term(cur) then return M.hide() end
  for _, buf in ipairs(recent) do
    if M.is_term(buf) and not M.win_of(buf) then return M.show(buf) end
  end
  for _, buf in ipairs(M.list()) do
    if not M.win_of(buf) then return M.show(buf) end
  end
  if recent[1] and M.is_term(recent[1]) then return M.show(recent[1]) end
  M.new()
end

-- Starting --------------------------------------------------------------------------

--- The directory the terminal's program is in now (a shell you cd'd around
--- in included), else Neovim's.
function M.cwd(buf)
  local ok, pid = pcall(vim.fn.jobpid, M.job(buf))
  if ok and pid > 0 then
    local link = vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
    if link then return link end
    local r = vim.system({ "lsof", "-a", "-p", tostring(pid), "-d", "cwd", "-Fn" }, { text = true }):wait(500)
    local dir = r.code == 0 and r.stdout and r.stdout:match("\nn([^\n]+)")
    if dir and vim.fn.isdirectory(dir) == 1 then return dir end
  end
  return vim.fn.getcwd()
end

--- Start a terminal and show it.
---   cmd   string (run through 'shell') or list; nil: your shell
---   opts  home ("bottom" | "right"), size, dir, name, focus, win (start it
---         in this window instead of a new one at its home),
---         close_on_exit (default: only for a plain shell), vars (buffer vars)
--- Returns the buffer.
function M.new(cmd, opts)
  opts = opts or {}
  local buf = api.nvim_create_buf(false, true)
  -- One started in a window you split gets its home worked out when hidden.
  vim.b[buf].term_home = opts.home or (not opts.win and "bottom" or nil)
  vim.b[buf].term_size = opts.size
  vim.b[buf].term_name = opts.name
  vim.b[buf].term_cmd = type(cmd) == "table" and table.concat(cmd, " ") or (cmd or vim.o.shell)
  local close = opts.close_on_exit
  if close == nil then close = cmd == nil end
  vim.b[buf].term_close_on_exit = close
  for k, v in pairs(opts.vars or {}) do vim.b[buf][k] = v end

  local win = opts.win
  if win then api.nvim_win_set_buf(win, buf) else win = place(buf) end
  local ok, err = pcall(api.nvim_win_call, win, function()
    vim.fn.jobstart(cmd or vim.o.shell, { term = true, cwd = opts.dir })
  end)
  if not ok then
    if not opts.win then pcall(api.nvim_win_close, win, true) end
    pcall(api.nvim_buf_delete, buf, { force = true })
    vim.notify("Could not start the terminal: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  style(win, buf)
  touch(buf)
  if opts.focus ~= false then
    api.nvim_set_current_win(win)
    vim.cmd("startinsert")
  end
  return buf
end

--- Stop the job and drop the buffer.
function M.kill(buf)
  if not M.is_term(buf) then return end
  local job = M.job(buf)
  if job then pcall(vim.fn.jobstop, job) end
  -- A window that must stay (the last one) gets another buffer first.
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf and #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win)) == 1 then
      api.nvim_win_set_buf(win, fallback_buffer(buf))
    end
  end
  pcall(api.nvim_buf_delete, buf, { force = true })
end

-- Keys ----------------------------------------------------------------------------

local function setup_keys()
  local map = vim.keymap.set
  -- A single <Esc>, with no second key to wait for. `term_typing` remembers
  -- that you chose normal mode, so coming back to this terminal keeps you
  -- there instead of dropping you into typing.
  map("t", "<Esc>", function()
    vim.b.term_typing = false
    return [[<C-\><C-n>]]
  end, { expr = true, desc = "Terminal: normal mode" })
  map("t", [[<C-\><Esc>]], function()
    local job = M.job(api.nvim_get_current_buf())
    if job then api.nvim_chan_send(job, "\27") end
  end, { desc = "Terminal: send Esc to the program" })

  map({ "n", "t" }, "<C-q>", M.toggle, { desc = "Terminal: hide / bring back (keeps running)" })

  local alt = require("config.alt")
  for dir, keys in pairs(alt.keys) do
    for _, lhs in ipairs(vim.list_extend({ "<C-w>" .. dir }, vim.deepcopy(keys))) do
      map("t", lhs, [[<C-\><C-n><C-w>]] .. dir, { desc = "Terminal: window " .. alt.names[dir] })
    end
  end
  -- Splitting while typing, like from normal mode (a new shell, see WinNew).
  for _, k in ipairs({ "s", "v" }) do
    map("t", "<C-w>" .. k, [[<C-\><C-n><C-w>]] .. k, { desc = "Terminal: split (new shell)" })
  end
  local resize = require("config.resize")
  for key in pairs(resize.ARROW_DIRS) do
    map("t", "<C-w>" .. key, function() resize.loop(key) end, { desc = "Terminal: resize (arrows, <Esc> stops)" })
  end

  map("n", "<leader>tt", function() require("config.termlist").open() end, { desc = "Terminals (list)" })

  -- :term / :terminal (they become :Term): on their own the terminal list,
  -- with a command that command in a new bottom row.
  api.nvim_create_user_command("Term", function(o)
    if o.args == "" then return require("config.termlist").open() end
    M.new(o.args, { home = "bottom" })
  end, { nargs = "*", complete = "shellcmd", desc = "Terminal list, or run a command in a new terminal" })
  for _, name in ipairs({ "terminal", "term" }) do
    vim.cmd(([[cnoreabbrev <expr> %s (getcmdtype() == ':' && getcmdline() ==# '%s') ? 'Term' : '%s']])
      :format(name, name, name))
  end
end

-- Events --------------------------------------------------------------------------

local group = api.nvim_create_augroup("Terminals", { clear = true })

local function setup_events()
  api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(ev)
      vim.bo[ev.buf].buflisted = false  -- not a tab in bufferline; <C-q> / <leader>tt find it
      if vim.b[ev.buf].term_cmd == nil then
        vim.b[ev.buf].term_cmd = vim.api.nvim_buf_get_name(ev.buf):match("^term://.-//%d+:(.*)$") or ""
      end
      local win = vim.fn.bufwinid(ev.buf)
      if win ~= -1 then style(win, ev.buf) end
      touch(ev.buf)
    end,
  })

  -- Typing again with i / a (or a click) is what puts it back in typing mode.
  api.nvim_create_autocmd("TermEnter", {
    group = group,
    callback = function(ev) vim.b[ev.buf].term_typing = true end,
  })

  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do style(win, ev.buf) end
    end,
  })

  -- Into a terminal: straight back to typing, unless you left it in normal mode.
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if not M.is_term(buf) then return end
      touch(buf)
      if vim.b[buf].term_typing == false or not M.running(buf) then return end
      vim.schedule(function()
        if api.nvim_get_current_buf() == buf and api.nvim_get_mode().mode == "n" then
          vim.cmd("startinsert")
        end
      end)
    end,
  })

  -- A split of a terminal (<C-w>s, <C-w>v, :split, :vsplit) would show the
  -- same session twice, mirrored. Like a tmux split, it gets a new shell
  -- instead, started where the terminal you split from is.
  api.nvim_create_autocmd("WinNew", {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      local buf = api.nvim_win_get_buf(win)
      if not M.is_term(buf) or api.nvim_win_get_config(win).relative ~= "" then return end
      local mirrored = false
      for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
        if w ~= win and api.nvim_win_get_buf(w) == buf then mirrored = true end
      end
      if not mirrored then return end
      vim.schedule(function()
        if not (api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf) then return end
        M.new(nil, { win = win, dir = M.cwd(buf), focus = api.nvim_get_current_win() == win })
      end)
    end,
  })

  -- However the window goes (<C-q>, <C-w>q, :q, :only), the terminal keeps
  -- running and comes back at this size.
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      if win and api.nvim_win_is_valid(win) then remember(win, api.nvim_win_get_buf(win)) end
    end,
  })

  -- A shell you exit, or a Claude that ends, takes its buffer with it. A
  -- command that fails keeps it, so you can read why.
  api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if vim.b[buf].term_close_on_exit and vim.v.event.status == 0 then
        vim.schedule(function() M.kill(buf) end)
      end
    end,
  })

  api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_highlights })
end

define_highlights()
setup_keys()
setup_events()

return M
