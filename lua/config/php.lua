-- Local PHP execution, aimed at LeetCode grinding: run the solution you are
-- writing through the `php` CLI and read the output in a split, without a
-- round-trip to leetcode.com.
--
-- Why this works with leetcode.nvim: it only ever submits the lines BETWEEN
-- `// @leet start` and `// @leet end`. Anything after the end marker is local
-- scaffolding -- it runs here and is never sent to LeetCode. So the workflow is
--
--     // @leet start
--     class Solution { function twoSum($nums, $target) { ... } }
--     // @leet end
--
--     $s = new Solution();          <- :PhpDriver writes this stub for you
--     print_r($s->twoSum([2,7,11,15], 9));
--
-- and :PhpRun prints the array. :PhpRepl opens a plain `php -a` shell for
-- one-off scratch expressions.

local M = {}

local TIMEOUT_MS = 10000

-- ---------------------------------------------------------------------------
-- Highlighting for tag-less PHP
--
-- LeetCode's snippets open straight at `class Solution` with no `<?php`. The
-- tree-sitter `php` grammar starts in text/HTML mode and only enters code at an
-- opening tag, so a tag-less buffer parses as ONE big text node: zero highlight
-- captures, and the file renders uncolored. `php_only` is the same grammar
-- entered at the code rule; point the highlighter at it when there's no tag.
-- The colours themselves already come from the palette in plugins/colorscheme.lua
-- -- php_only's queries use the standard @keyword / @function / @variable
-- captures that file already maps.
-- ---------------------------------------------------------------------------

local SCAN_LINES = 200

--- True when the buffer looks like bare PHP code with no `<?php` / `<?=` tag.
--- Bails on anything that opens with markup -- that's a template whose leading
--- HTML the normal `php` parser handles correctly.
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

--- Swap a tag-less PHP buffer onto the php_only highlighter. Idempotent.
--- @param buf integer
local function use_php_only(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.bo[buf].filetype ~= "php" then return end
  if vim.b[buf].php_only_hl then return end
  if not tagless_php(buf) then return end
  -- Not installed yet (fresh machine, :TSUpdate still running) -> leave the
  -- buffer on the default parser rather than tearing its highlighter down.
  if not pcall(vim.treesitter.language.add, "php_only") then return end

  pcall(vim.treesitter.stop, buf)
  if pcall(vim.treesitter.start, buf, "php_only") then
    vim.b[buf].php_only_hl = true
  end
end

-- FileType alone isn't enough for leetcode.nvim: it fills the question buffer
-- after the event fires, so the scan above would run against an empty buffer.
-- BufWinEnter catches it once the content is really there; the b: guard keeps
-- the repeat visits free.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "php",
  callback = function(ev) vim.schedule(function() use_php_only(ev.buf) end) end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*.php",
  callback = function(ev) vim.schedule(function() use_php_only(ev.buf) end) end,
})

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
  -- Buffer-local close keys. <leader>q / <leader>x are shadowed on purpose:
  -- the global ones (config/keymaps.lua smart_close) DELETE the buffer and
  -- swap another one into the window, which would leave the split sitting
  -- there showing a random file. Here the window itself should go away.
  for _, lhs in ipairs({ "q", "ZZ", "<leader>q", "<leader>x" }) do
    vim.keymap.set("n", lhs, "<cmd>close<cr>", { buffer = buf, desc = "Close PHP output" })
  end
  return buf
end

--- Write `lines` into the output pane, opening it below the editor if it isn't
--- already on screen. Focus stays where it was -- you keep typing in the code.
--- @param lines string[]
local function show(lines)
  local buf = output_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  -- Leave it unmodified so ZZ (:x) closes the window instead of failing with
  -- E382 "Cannot write, 'buftype' option is set".
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
    vim.wo[win].colorcolumn = ""      -- no line-length rule in output
  end
  -- Focus the pane: you read the result, then close it with q / ZZ /
  -- <leader>q without a window hop first.
  vim.api.nvim_set_current_win(win)
  pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
end

--- Buffer contents as a standalone runnable script. LeetCode's PHP snippets
--- start straight at `class Solution` with no opening tag, so add one.
---
--- The tag is spliced onto the FRONT of the first non-blank line rather than
--- inserted as a line of its own: that keeps the temp file line-for-line
--- identical to the buffer, so line numbers in a PHP stack trace point at the
--- line you are actually looking at.
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

  -- log_errors=0: the CLI otherwise reports every fatal TWICE, once via
  -- display_errors (stdout) and once via the error log (stderr).
  -- :wait(TIMEOUT_MS) kills the process if it overruns, so an accidental
  -- infinite loop in a solution can't wedge the editor.
  local res = vim.system({ "php", "-d", "log_errors=0", tmp }, { text = true }):wait(TIMEOUT_MS)
  vim.fn.delete(tmp)

  local out = { ("── php %s · exit %d ──"):format(name, res.code) }
  for _, chunk in ipairs({ res.stdout, res.stderr }) do
    if chunk and chunk ~= "" then
      -- Stack traces name the temp file; show the buffer's name instead so the
      -- "in <file> on line N" reads against the file you're editing. The
      -- /private form goes first: on macOS tempname() hands back /var/... but
      -- PHP reports the resolved /private/var/..., and replacing the short
      -- form first would leave a stray "/private" glued to the name.
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

--- Append a driver stub after `// @leet end`, pre-filled with the first public
--- method found in the buffer so it is one edit away from runnable.
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
