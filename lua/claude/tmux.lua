-- Thin wrapper around the tmux CLI. Every Claude session lives in a tmux pane:
-- the ones started from Neovim in hidden sessions of their own, plus any
-- Claude you started by hand in some other pane. Sessions survive Neovim
-- restarts, and every Neovim on the machine sees the same ones.

local M = {}

-- Process names (ps comm, tmux pane_current_command) that count as Claude.
-- Homebrew's build reports "claude.exe"; the nix wrapper ".claude-wrapped".
M.commands = { claude = true, ["claude.exe"] = true, [".claude-wrapped"] = true }

-- Prefix of the throwaway grouped sessions the side panel attaches through.
M.VIEW_PREFIX = "nvimview-"

function M.available()
  return vim.fn.executable("tmux") == 1
end

--- Run tmux asynchronously; cb(ok, stdout, stderr) on the main loop.
function M.run(args, cb)
  vim.system(vim.list_extend({ "tmux" }, args), { text = true }, function(r)
    if cb then
      vim.schedule(function() cb(r.code == 0, r.stdout or "", r.stderr or "") end)
    end
  end)
end

--- Run tmux and wait for it. Returns ok, stdout (trimmed), stderr.
function M.run_sync(args)
  local r = vim.system(vim.list_extend({ "tmux" }, args), { text = true }):wait()
  return r.code == 0, vim.trim(r.stdout or ""), vim.trim(r.stderr or "")
end

-- Panes ---------------------------------------------------------------------

-- Title last: it is free text Claude sets (the conversation topic) and is the
-- only field that could ever contain the separator.
local FIELDS = {
  "pane_id", "pane_tty", "pane_current_command", "pane_current_path",
  "session_name", "window_index", "pane_index",
  "@claude_name", "@claude_color", "@claude_owned", "pane_title",
}
local FMT = "#{" .. table.concat(FIELDS, "}\t#{") .. "}"

--- ttys (without /dev/) that have a Claude process on them. The nix wrapper
--- makes pane_current_command say "bash", so look at every process too.
local function claude_ttys(cb)
  vim.system({ "ps", "-eo", "tty=,comm=" }, { text = true }, function(r)
    local set = {}
    if r.code == 0 then
      for line in r.stdout:gmatch("[^\n]+") do
        local tty, comm = line:match("^%s*(%S+)%s+(.-)%s*$")
        if tty and M.commands[vim.fs.basename(comm or "")] then set[tty] = true end
      end
    end
    vim.schedule(function() cb(set) end)
  end)
end

--- cb(list) with every pane running Claude:
---   { id, tty, path, session, window, loc, name?, color?, owned, title }
--- A pane shown through a grouped session (the side panel) is listed once,
--- under its real session.
function M.claude_panes(cb)
  M.run({ "list-panes", "-a", "-F", FMT }, function(ok, out)
    if not ok then return cb({}) end
    claude_ttys(function(ttys)
      local by_id, order = {}, {}
      for line in out:gmatch("[^\n]+") do
        local f = vim.split(line, "\t", { plain = true })
        if #f > #FIELDS then f[#FIELDS] = table.concat(f, "\t", #FIELDS) end
        local id, tty, cmd = f[1], (f[2] or ""):gsub("^/dev/", ""), f[3]
        if id and (M.commands[cmd] or ttys[tty]) then
          local p = by_id[id]
          local is_view = vim.startswith(f[5], M.VIEW_PREFIX)
          if not p or (p.via_view and not is_view) then
            p = {
              id = id, tty = tty, path = f[4], session = f[5],
              window = f[6], loc = ("%s:%s.%s"):format(f[5], f[6], f[7]),
              name = f[8] ~= "" and f[8] or nil,
              color = tonumber(f[9]),
              owned = f[10] == "1",
              title = f[11] or "",
              via_view = is_view,
            }
            if not by_id[id] then order[#order + 1] = id end
            by_id[id] = p
          end
        end
      end
      local list = {}
      for _, id in ipairs(order) do list[#list + 1] = by_id[id] end
      cb(list)
    end)
  end)
end

--- cb(text) with what the pane shows right now ("" if it is gone).
function M.capture(pane, cb)
  M.run({ "capture-pane", "-p", "-t", pane }, function(ok, out) cb(ok and out or "") end)
end

--- Pane-scoped user options travel with the pane, so a name given in one
--- Neovim shows up in every other one.
function M.set_pane_options(pane, opts)
  local args = {}
  for k, v in pairs(opts) do
    if #args > 0 then args[#args + 1] = ";" end
    vim.list_extend(args, { "set-option", "-p", "-t", pane, "@" .. k, tostring(v) })
  end
  if #args > 0 then M.run(args) end
end

function M.pane_alive(pane)
  local ok, out = M.run_sync({ "display-message", "-p", "-t", pane, "#{pane_id}" })
  return ok and out == pane
end

function M.has_session(name)
  return (M.run_sync({ "has-session", "-t", "=" .. name }))
end

-- Starting / stopping ---------------------------------------------------------

--- New detached session running `cmd` in `dir`. Claude is the session's only
--- process, so the session ends when you /exit. `opts` become pane options in
--- the same tmux command, so no scan can ever see the pane without them.
--- Returns pane id, window index.
function M.new_session(name, dir, cmd, size, opts)
  local args = {
    "new-session", "-d", "-P", "-F", "#{pane_id} #{window_index}",
    "-s", name, "-c", dir, "-x", tostring(size.w), "-y", tostring(size.h), cmd,
    ";", "set-option", "-t", name, "status", "off",
  }
  for k, v in pairs(opts or {}) do
    vim.list_extend(args, { ";", "set-option", "-p", "-t", name .. ":", "@" .. k, tostring(v) })
  end
  local ok, out, err = M.run_sync(args)
  if not ok then return nil, err end
  local pane, window = out:match("^(%%%d+) (%d+)")
  if not pane then return nil, "unexpected tmux output: " .. out end
  return pane, window
end

--- Replace whatever runs in the pane with `cmd`, started in `dir`. The pane
--- (and its name/colour options) stays; the old process is killed.
function M.respawn(pane, dir, cmd)
  return M.run_sync({ "respawn-pane", "-k", "-t", pane, "-c", dir, cmd })
end

function M.kill_pane(pane)
  return M.run_sync({ "kill-pane", "-t", pane })
end

--- Command for a terminal job that attaches to the pane through a throwaway
--- grouped session: its own current window (so the real session's view is not
--- switched), no prefix key and no status bar (so tmux is invisible), and gone
--- as soon as the job ends (destroy-unattached).
function M.attach_cmd(p)
  local grp = M.VIEW_PREFIX .. p.id:gsub("%%", "") .. "-" .. vim.uv.hrtime() % 1000000
  return {
    "tmux", "new-session", "-t", "=" .. p.session, "-s", grp,
    ";", "set-option", "-t", grp, "prefix", "None",
    ";", "set-option", "-t", grp, "status", "off",
    ";", "set-option", "-t", grp, "destroy-unattached", "on",
    ";", "select-window", "-t", "=" .. grp .. ":" .. p.window,
    ";", "select-pane", "-t", p.id,
  }
end

return M
