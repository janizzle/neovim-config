-- Debugger: Xdebug 3 through vscode-php-debug (mason's php-debug-adapter).
-- <leader>bc starts listening on 9003; then hit the page / run the CLI with
-- XDEBUG_SESSION set and execution stops at your breakpoints.
--
-- Panels sit in one tray along the bottom, under the tree and the code, so
-- the code keeps its full height and width and the values get the most room:
--
--   +-----------+--------------------------------------------------------+
--   | file tree |  code  (values of variables shown at the line ends)    |
--   +-----------+--------------+-----------+-----------+-----------------+
--   | VARIABLES                | WATCHES   | CALL      | BREAKPOINTS     |
--   | (widest)                 |           | STACK     |                 |
--   +--------------------------+-----------+-----------+-----------------+
--
-- The console (evaluate anything) opens on the right on demand: <leader>br.
-- The tray opens when a session starts and whenever execution stops at a
-- breakpoint or exception, closes when the session ends, and <leader>l closes
-- it along with everything else. Stepping never reopens it, so once you have
-- hidden it (<leader>bu) it stays out of the way while you step.

local M = {}

local api = vim.api
local TRAY, CONSOLE = 1, 2

local TITLES = {
  dapui_scopes      = { "VARIABLES",   "<cr> expand · e edit · r to console" },
  dapui_watches     = { "WATCHES",     "i add · e edit · d remove" },
  dapui_stacks      = { "CALL STACK",  "<cr> go to frame" },
  dapui_breakpoints = { "BREAKPOINTS", "<cr> go to · t toggle · d remove" },
  ["dap-repl"]      = { "CONSOLE",     "type an expression, <cr> evaluates" },
}

local function define_highlights()
  local C = require("config.palette")
  local set = function(n, o) api.nvim_set_hl(0, n, o) end
  set("DapPanelTitle", { fg = C.blue, bg = C.bg_alt, bold = true })
  set("DapPanelHint", { fg = C.line_nr, bg = C.bg_alt })
  set("DapStoppedLine", { bg = "#2A2614" })
  set("DapStoppedSign", { fg = C.tag, bold = true })
  set("DapLogPointSign", { fg = C.blue })
  set("DapRejectedSign", { fg = C.line_nr })
  -- Inline values (nvim-dap-virtual-text): quiet, changed ones stand out.
  set("NvimDapVirtualText", { fg = C.unused, italic = true })
  set("NvimDapVirtualTextChanged", { fg = C.tag, italic = true })
end

--- Name each panel and say which keys it takes; dap-ui leaves them untitled.
local function title_panels()
  for _, win in ipairs(api.nvim_list_wins()) do
    local t = TITLES[vim.bo[api.nvim_win_get_buf(win)].filetype]
    if t and api.nvim_win_get_config(win).relative == "" then
      vim.wo[win].winbar = "%#DapPanelTitle# " .. t[1] .. " %#DapPanelHint# " .. t[2] .. "%#DapPanelHint#"
    end
  end
end

local function layout_open(i)
  local ok, windows = pcall(require, "dapui.windows")
  return ok and windows.layouts[i] ~= nil and windows.layouts[i]:is_open()
end

--- dap-ui splits off the current window, which fails in a float (a picker)
--- and lands oddly next to a terminal: build from the editor window instead.
local function from_editor(fn)
  if api.nvim_win_get_config(0).relative == "" then return fn() end
  local win = require("config.windows").find_main_window()
  if win then api.nvim_win_call(win, fn) end
end

function M.open()
  from_editor(function() require("dapui").open({ layout = TRAY, reset = true }) end)
  title_panels()
end

function M.close()
  require("dapui").close()
end

function M.toggle()
  if layout_open(TRAY) then require("dapui").close({ layout = TRAY }) else M.open() end
end

function M.toggle_console()
  from_editor(function() require("dapui").toggle({ layout = CONSOLE, reset = true }) end)
  title_panels()
end

--- What to evaluate: the selection, else the expression under the cursor.
--- PHP's 'iskeyword' has no `$`, so <cexpr> on $user->name would be
--- "user->name", which Xdebug reads as a constant.
local function cursor_expr()
  local mode = api.nvim_get_mode().mode
  if mode:match("^[vV\22]") then
    local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    return table.concat(lines, "\n")
  end
  local isk = vim.bo.iskeyword
  if vim.bo.filetype == "php" then vim.bo.iskeyword = isk .. ",$" end
  local expr = vim.fn.expand("<cexpr>")
  vim.bo.iskeyword = isk
  return expr
end

function M.setup()
  local dap = require("dap")
  local dapui = require("dapui")
  local mason = require("config.mason")

  mason.ensure({ "php-debug-adapter" })

  -- A function, so the binary is looked up per session: on a fresh machine
  -- mason may still be installing it when this config runs.
  dap.adapters.php = function(callback)
    callback({ type = "executable", command = mason.cmd("php-debug-adapter") })
  end
  dap.configurations.php = {
    { type = "php", request = "launch", name = "Listen for Xdebug", port = 9003 },
  }

  dapui.setup({
    -- Keys are listed in each panel's title instead of dap-ui's button bar.
    controls = { enabled = false },
    floating = { border = "rounded" },
    layouts = {
      {
        position = "bottom",
        size = 15,
        elements = {
          { id = "scopes", size = 0.45 },
          { id = "watches", size = 0.2 },
          { id = "stacks", size = 0.2 },
          { id = "breakpoints", size = 0.15 },
        },
      },
      {
        position = "right",
        size = 60,
        elements = { { id = "repl", size = 1 } },
      },
    },
  })

  local ok, vt = pcall(require, "nvim-dap-virtual-text")
  if ok then
    vt.setup({
      virt_text_pos = "eol",       -- after the code, never pushing it sideways
      highlight_changed_variables = true,
      show_stop_reason = true,
      commented = false,
    })
  end

  dap.listeners.after.event_initialized.layout = function() M.open() end
  dap.listeners.after.event_stopped.layout = function(_, body)
    -- A breakpoint or exception wants your attention; a step does not.
    if body and body.reason ~= "step" and not layout_open(TRAY) then M.open() end
  end
  dap.listeners.before.event_terminated.layout = M.close
  dap.listeners.before.event_exited.layout = M.close
  dap.listeners.before.disconnect.layout = M.close
  -- Panels opened any other way (dap-ui's own toggle) get their titles too.
  api.nvim_create_autocmd("FileType", {
    pattern = vim.tbl_keys(TITLES),
    callback = function() vim.schedule(title_panels) end,
  })

  define_highlights()
  api.nvim_create_autocmd("ColorScheme", { callback = define_highlights })
  vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError" })
  vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError" })
  vim.fn.sign_define("DapLogPoint", { text = "◉", texthl = "DapLogPointSign" })
  vim.fn.sign_define("DapBreakpointRejected", { text = "○", texthl = "DapRejectedSign" })
  vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DapStoppedSign", linehl = "DapStoppedLine" })

  local function map(lhs, rhs, desc, mode)
    vim.keymap.set(mode or "n", lhs, rhs, { desc = "Debug: " .. desc })
  end
  map("<leader>bc", dap.continue, "start / continue")
  map("<leader>bq", dap.terminate, "stop")
  map("<leader>bb", dap.toggle_breakpoint, "toggle breakpoint")
  map("<leader>bB", function()
    vim.ui.input({ prompt = "Break when: " }, function(cond)
      if cond and cond ~= "" then dap.set_breakpoint(cond) end
    end)
  end, "conditional breakpoint")
  map("<leader>bl", function()
    vim.ui.input({ prompt = "Log message ({$var} is replaced): " }, function(msg)
      if msg and msg ~= "" then dap.set_breakpoint(nil, nil, msg) end
    end)
  end, "log point (prints, doesn't stop)")
  map("<leader>bX", dap.clear_breakpoints, "clear all breakpoints")
  map("<leader>bo", dap.step_over, "step over")
  map("<leader>bi", dap.step_into, "step into")
  map("<leader>bO", dap.step_out, "step out")
  map("<leader>bC", dap.run_to_cursor, "run to cursor")
  map("<leader>be", function() dapui.eval(cursor_expr()) end,
    "evaluate under cursor (again to enter)", { "n", "x" })
  map("<leader>bw", function()
    local expr = cursor_expr()
    if expr ~= "" then
      dapui.elements.watches.add(expr)
      if not layout_open(TRAY) then M.open() end
    end
  end, "watch expression under cursor", { "n", "x" })
  map("<leader>bu", M.toggle, "toggle panels")
  map("<leader>br", M.toggle_console, "toggle console")
end

return M
