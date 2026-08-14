-- Start screen painted into the empty scratch buffer on launch
-- (wired up by config/layout.lua via require("welcome").paint(buf)).
--
-- The cheat sheet is built from tables rather than hand-spaced strings: every
-- column then lines up by construction, and adding a key later can't quietly
-- knock the section it lives in out of alignment.

local M = {}

-- Layout ----------------------------------------------------------------------

local INDENT = "      "   -- key rows
local HEAD   = "    "     -- section rules
local KEY_W  = 15         -- widest key we show (":MergeMarkers")
local COL_W  = 35         -- start of the second column, from INDENT
local CMD_W  = 22         -- command column in the :Command sections
local WIDTH  = 62         -- section rules run to here

-- Display width, not byte length: the descriptions contain "·" and "…", and
-- counting those as three columns each is exactly how a table of keys drifts
-- out of alignment one row at a time.
local function pad(s, w)
  return s .. string.rep(" ", math.max(1, w - vim.fn.strdisplaywidth(s)))
end

--- One or two `key -- what it does` cells on a line.
local function row(k1, d1, k2, d2)
  local left = pad(k1, KEY_W) .. d1
  if not k2 then return INDENT .. left end
  return INDENT .. pad(left, COL_W) .. pad(k2, KEY_W) .. d2
end

--- A `:command -- what it does` line, for the sections that are commands
--- rather than keys.
local function cmd(name, desc)
  return INDENT .. pad(name, CMD_W) .. desc
end

local function head(title)
  return HEAD .. "── " .. title .. " " .. string.rep("─", math.max(3, WIDTH - #title - 4))
end

local function note(text)
  return INDENT .. "  " .. text
end

-- Content ---------------------------------------------------------------------

local banner = {
  "",
  "",
  -- Vim's mark: V + "im" strokes on the shaded diamond backdrop.
  "                                              ░",
  "                                            ░░░░░",
  "                              ██████    ██████░░░░░",
  "                              ██████   ░██████░░░░░░░░",
  "   ███╗   ██╗███████╗ ██████╗  ████  ░░░░████░░░░░░░░░░░",
  "   ████╗  ██║██╔════╝██╔═══██╗ ████░░░░████░░███░░░░░░░░░░",
  "   ██╔██╗ ██║█████╗  ██║   ██║ ████░░████░░░░░░░░░░░░░░░░░░░",
  "   ██║╚██╗██║██╔══╝  ██║   ██║ ████████░░░░███░░███░███░███░░░",
  "   ██║ ╚████║███████╗╚██████╔╝ ██████░░░░░███░░███░███░███░░",
  "   ╚═╝  ╚═══╝╚══════╝ ╚═════╝  ████░░░░░░███░░███░███░███░",
  "                               ██    ░░░███░░███░███░███",
  "                                       ███░░███░███░███",
  "                                          ░░░░░░░░░",
  "                                            ░░░░░",
  "                                              ░",
  "",
}

-- Ordered by how often you reach for it, and every section is one job: find
-- something, move around, read code, see what changed, resolve a merge.
local sections = {
  { "Files & search", {
    row("<space>ff", "Find files",        "<space>fg", "Live grep"),
    row("<space>fw", "Grep word",         "<space>fb", "Switch buffers"),
    row("<space>fd", "Find directory",    "<space>fh", "Help tags"),
  }},

  { "Buffers & windows", {
    row("<space>s",    "Save",            "<space>x",    "Save & close"),
    row("<space>q",    "Force close",     "<space>X",    "Close, discard"),
    row("Shift-h/l",   "Prev / next tab", "<space>l",    "Restore layout"),
    row("<space>w1-9", "Jump to window",  "<space>t1-9", "Jump to buffer tab"),
    row(":qa",         "Quit all"),
  }},

  { "Code (LSP)", {
    row("gd",         "Go to definition", "gr",         "Find references"),
    row("K",          "Hover docs",       "gD gi gy",   "Decl · impl · type"),
    row("[d ]d",      "Prev / next diagnostic"),
    row("<space>rn",  "Rename symbol",    "<space>ca",  "Code action"),
  }},

  { "File tree", {
    row("a",  "New file (a…/ dir)", "r",    "Rename"),
    row("d",  "Delete",             "<cr>", "Open"),
  }},

  { "Git changes", {
    row("<space>gs",    "Changed files",   "<space>gb", "Blame column"),
    row("]c [c",        "Next / prev hunk", "<space>cn cp", "Same, no AltGr"),
    row("<space>hp",    "Preview change",  "<space>hi", "Preview inline"),
    row("<space>hs",    "Stage hunk",      "<space>hr", "Reset hunk"),
    row("<space>hS",    "Stage file",      "<space>hR", "Reset file"),
    row("<space>hb",    "Blame line",      "<space>hB", "Inline blame"),
    row("<space>hw",    "Word diff",       "<space>hL", "Line highlight"),
  }},

  { "Diff & merge", {
    row("<space>ds", "This file vs HEAD", "<space>dv", "All changes"),
    row("<space>dc", "Last commit",       "<space>dh", "File history"),
    row("<space>dH", "Repo history",      "<space>dx", "Conflicts (qf)"),
    row("<space>dm", "Merge workspace",   "<space>dq", "Close any diff"),
    "",
    note("in <space>dm: red = conflict · blue = ours · purple = theirs"),
    row("ct",     "Take theirs",  "co",     "Take ours"),
    row("cb",     "Take both",    "cB",     "Take base"),
    row("c0",     "Drop block",   "cn cp",  "Next / prev block"),
    row(":w",     "Write result", ":MergeMarkers", "Markers back"),
  }},

  { "LeetCode", {
    cmd(":Leet",         "Open the dashboard"),
    cmd(":Leet list",    "Pick a question   ·   :Leet daily"),
    cmd(":Leet lang",    "Switch language (php, python3, ...)"),
    cmd(":Leet run",     "Run LeetCode's testcases (remote)"),
    cmd(":Leet submit",  "Submit the solution"),
    cmd(":Leet console", "Custom testcase + result panes (remote)"),
    cmd(":Leet desc",    "Toggle the question description"),
    cmd(":Leet cookie update", "Sign in (paste the session cookie)"),
  }},

  { "Run PHP locally", {
    cmd(":PhpRun",    "Run this buffer through the php CLI"),
    cmd(":PhpDriver", "Append a driver stub to call your Solution"),
    cmd(":PhpRepl",   "Interactive php -a shell in a split"),
  }},

  { "Project commands", {
    cmd("Unit tests",        "phpunit -c phpunit-unit.xml"),
    cmd("Integration tests", "phpunit -c phpunit-integration.xml"),
    cmd("Single test",       "phpunit -c phpunit-unit.xml --filter <name>"),
    cmd("JS tests",          "npm run jstest  ·  npm run jstest-coverage"),
    cmd("E2E tests",         "npx nightwatch"),
    cmd("Static analysis",   "vendor/bin/phpstan analyse"),
    cmd("Build assets",      "npm run build  ·  watch: npm run watch"),
  }},
}

local lines = vim.deepcopy(banner)
for _, section in ipairs(sections) do
  lines[#lines + 1] = head(section[1])
  lines[#lines + 1] = ""
  vim.list_extend(lines, section[2])
  lines[#lines + 1] = ""
end

--- Paint the welcome screen into an empty, unnamed scratch buffer.
--- No-op if the buffer already holds a file or content.
--- @param buf integer buffer handle
function M.paint(buf)
  if vim.api.nvim_buf_get_name(buf) ~= "" then return end
  if vim.bo[buf].buftype ~= "" then return end
  if vim.api.nvim_buf_line_count(buf) > 1 then return end
  local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
  if first ~= "" then return end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  -- Read by bufferline/lualine to label this buffer "Welcome". A buffer
  -- variable, not a :file name -- a real name would make :update try to
  -- write a file called "Welcome" into the cwd.
  vim.b[buf].welcome_screen = true
  -- The banner is drawn with spaces; re-run the `list` normalizer from
  -- config/options.lua now that the flag is set, so it isn't dot-filled.
  vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, modeline = false })
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = buf,
    once = true,
    callback = function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.bo[buf].modified = false
      vim.b[buf].welcome_screen = nil
      vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = buf, modeline = false })
    end,
  })
end

return M
