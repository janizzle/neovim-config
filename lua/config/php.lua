-- PHP helpers for LeetCode grinding: make the plugin's tag-less snippets
-- behave like normal PHP files, and run solutions locally through the `php`
-- CLI (:PhpRun / :PhpDriver / :PhpRepl) without a round-trip to leetcode.com.
--
-- Local runs compose with leetcode.nvim because :Leet submit only sends the
-- lines BETWEEN `// @leet start` and `// @leet end`; anything outside the
-- markers (the injected `<?php`, the :PhpDriver stub) stays local.

local M = {}

local TIMEOUT_MS = 10000
local SCAN_LINES = 200

-- ---------------------------------------------------------------------------
-- `<?php` injection. LeetCode snippets open straight at `// @leet start` with
-- no tag, and the tree-sitter php grammar only enters code mode at an opening
-- tag -- a tag-less buffer parses as one big text node: no highlighting, and
-- an indentexpr that answers 0 (every <CR> lands at column 0). Inserting
-- `<?php` as line 1 makes it a normal PHP file and fixes both at once.
-- ---------------------------------------------------------------------------

--- True when the buffer looks like bare PHP with no `<?php` / `<?=` tag.
--- Bails on anything that opens with markup (a template's leading HTML is
--- handled correctly by the php parser as-is).
--- @param buf integer
local function tagless_php(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, SCAN_LINES, false)
  local saw_code = false
  for _, line in ipairs(lines) do
    if line:find("<?", 1, true) then return false end
    if not saw_code and line:match("%S") then
      saw_code = true
      if line:match("^%s*<") then return false end
    end
  end
  return saw_code
end

--- Insert `<?php` as line 1 of a tag-less LeetCode solution buffer.
--- Idempotent: once the tag is there, tagless_php() says no next time.
--- @param buf integer
local function inject_php_tag(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.bo[buf].filetype ~= "php" then return end
  if not tagless_php(buf) then return end

  -- Only leetcode solutions -- a random tag-less .php buffer isn't ours to edit.
  local leet = false
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, SCAN_LINES, false)) do
    if line:find("@leet start", 1, true) then leet = true break end
  end
  if not leet then return end

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "<?php" })
end

-- FileType alone isn't enough for leetcode.nvim: it fills the question buffer
-- after that event fires, so the scan would run against an empty buffer.
-- BufWinEnter catches it once the content is really there.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  callback = function(ev) vim.schedule(function() inject_php_tag(ev.buf) end) end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*.php",
  callback = function(ev) vim.schedule(function() inject_php_tag(ev.buf) end) end,
})

-- ---------------------------------------------------------------------------
-- Local execution
-- ---------------------------------------------------------------------------

--- The output pane's scratch buffer, created on first use and reused after.
local function output_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].php_output then
      return buf
    end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.b[buf].php_output = true
  -- <leader>q / <leader>x shadowed on purpose: the global smart_close would
  -- swap another buffer into the split; here the window itself should go.
  for _, lhs in ipairs({ "q", "ZZ", "<leader>q", "<leader>x" }) do
    vim.keymap.set("n", lhs, "<cmd>close<cr>", { buffer = buf, desc = "Close PHP output" })
  end
  return buf
end

--- Show `lines` in the output pane below the editor and focus it (close with
--- q / ZZ / <leader>q without a window hop).
--- @param lines string[]
local function show(lines)
  local buf = output_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  -- Unmodified so ZZ closes the window instead of failing with E382.
  vim.bo[buf].modified = false

  local win
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(w) == buf then
      win = w
      break
    end
  end

  if not win then
    vim.cmd("botright " .. math.max(8, math.min(20, #lines + 1)) .. "split")
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].winfixheight = true
    vim.wo[win].colorcolumn = ""
  end
  vim.api.nvim_set_current_win(win)
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
end

--- Buffer contents as a standalone runnable script. If the buffer somehow has
--- no `<?php`, splice one onto the FRONT of the first non-blank line -- not a
--- line of its own -- so the temp file stays line-for-line identical to the
--- buffer and PHP stack-trace line numbers match what you're looking at.
--- @param buf integer
--- @return string[]
local function source(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local first = 1
  while first <= #lines and lines[first]:match("^%s*$") do
    first = first + 1
  end
  if lines[first] and not lines[first]:match("^%s*<%?php") then
    lines[first] = "<?php " .. lines[first]
  elseif not lines[first] then
    lines[#lines + 1] = "<?php"
  end
  return lines
end

--- Run the current PHP buffer and show stdout + stderr in the output pane.
function M.run()
  if vim.bo.filetype ~= "php" then
    vim.notify("PhpRun: current buffer is not PHP", vim.log.levels.WARN)
    return
  end
  if vim.fn.executable("php") == 0 then
    vim.notify("PhpRun: `php` is not in $PATH", vim.log.levels.ERROR)
    return
  end

  local tmp = vim.fn.tempname() .. ".php"
  if vim.fn.writefile(source(0), tmp) ~= 0 then
    vim.notify("PhpRun: could not write " .. tmp, vim.log.levels.ERROR)
    return
  end

  local name = vim.fn.expand("%:t")
  if name == "" then name = "buffer" end

  -- log_errors=0: the CLI otherwise reports every fatal twice (display_errors
  -- + error log). :wait() kills overruns so an infinite loop can't wedge nvim.
  local res = vim.system({ "php", "-d", "log_errors=0", tmp }, { text = true }):wait(TIMEOUT_MS)
  vim.fn.delete(tmp)

  local out = { ("── php %s · exit %d ──"):format(name, res.code) }
  for _, chunk in ipairs({ res.stdout, res.stderr }) do
    if chunk and chunk ~= "" then
      -- Rewrite the temp path in stack traces to the buffer's name. /private
      -- form first: macOS tempname() returns /var/... but PHP reports the
      -- resolved /private/var/..., and replacing the short form first would
      -- leave a stray "/private" glued to the name.
      chunk = chunk:gsub(vim.pesc("/private" .. tmp), name):gsub(vim.pesc(tmp), name)
      chunk = chunk:gsub("%s+$", "")
      vim.list_extend(out, vim.split(chunk, "\n", { plain = true }))
    end
  end
  if #out == 1 then
    vim.list_extend(out, {
      "(no output -- a bare `class Solution` never calls itself)",
      "Add a driver after `// @leet end`, or run :PhpDriver to insert a stub.",
    })
  end
  show(out)
end

--- Append a driver stub after the solution, pre-filled with the first public
--- method found so it is one edit away from runnable.
function M.driver()
  if vim.bo.filetype ~= "php" then
    vim.notify("PhpDriver: current buffer is not PHP", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("^%s*%$s%s*=%s*new%s+Solution") then
      vim.notify("PhpDriver: driver block already present", vim.log.levels.INFO)
      return
    end
  end

  local method = "solve"
  for _, line in ipairs(lines) do
    local m = line:match("function%s+([%w_]+)%s*%(")
    if m and m ~= "__construct" then
      method = m
      break
    end
  end

  vim.api.nvim_buf_set_lines(0, #lines, #lines, false, {
    "",
    "// --- local driver: after `@leet end`, so :Leet submit never sees it ---",
    "$s = new Solution();",
    ("print_r($s->%s());"):format(method),
  })
  vim.api.nvim_win_set_cursor(0, { #lines + 4, 0 })
end

--- Interactive `php -a` shell in a split below.
function M.repl()
  if vim.fn.executable("php") == 0 then
    vim.notify("PhpRepl: `php` is not in $PATH", vim.log.levels.ERROR)
    return
  end
  vim.cmd("botright 15split")
  vim.cmd("terminal php -a")
  vim.cmd("startinsert")
end

vim.api.nvim_create_user_command("PhpRun", M.run, { desc = "Run current PHP buffer" })
vim.api.nvim_create_user_command("PhpDriver", M.driver, { desc = "Insert a local PHP driver stub" })
vim.api.nvim_create_user_command("PhpRepl", M.repl, { desc = "Interactive php -a shell" })

return M
