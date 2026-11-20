-- The terminal list (:term, <leader>tt): every terminal that is not a Claude
-- session -- those have a list of their own, <leader>cc -- whether it is on
-- screen or hidden, and a row to start a new one.
--
--   <cr> show · n new terminal · r rename · x kill · q / <Esc> close
--   (moving around: see config/menu.lua)

local api = vim.api
local menu = require("config.menu")
local term = require("config.term")

local M = {}

M.FILETYPE = "termlist" -- listed in hardtime's disabled_filetypes

local ICON = vim.fn.nr2char(0xF489) -- nf-oct-terminal
local KEYS = " <cr> show · n new · r rename · x kill · <Esc> close "

local function rows()
  local out = {}
  for _, buf in ipairs(term.list()) do
    if not term.owned(buf) then out[#out + 1] = { id = buf, buf = buf } end
  end
  out[#out + 1] = { id = "new" }
  return out
end

local function cols(r, i)
  if r.buf then
    local running = term.running(r.buf)
    return {
      { tostring(i), "TermHint" },
      { ICON, "TermTitle" },
      { term.name(r.buf), "TermTitle" },
      { running and "running" or "exited", running and "TermHint" or "DiagnosticError" },
      { term.win_of(r.buf) and "on screen" or "hidden", "TermHint" },
      { term.title(r.buf), "TermDim" },
    }
  end
  return {
    { "+", "DiagnosticOk" }, { "" }, { "New terminal" }, { "" }, { "" },
    { "a shell in " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":~"), "TermDim" },
  }
end

function M.open()
  local cur = api.nvim_get_current_buf()

  local function show(r, m)
    if not r then return end
    m.close()
    if r.buf then term.show(r.buf) else term.new() end
  end

  menu.open({
    title = { { " " .. ICON .. " Terminals ", "TermTitle" } },
    footer = KEYS, footer_hl = "TermHint",
    filetype = M.FILETYPE, rows = rows, cols = cols,
    select = term.is_term(cur) and cur or nil,
    keys = {
      ["<cr>"] = show, o = show, ["<2-LeftMouse>"] = show,
      n = function(_, m) m.close() term.new() end,
      r = function(r, m)
        if not (r and r.buf) then return end
        vim.ui.input({ prompt = "Rename terminal to: ", default = term.name(r.buf) }, function(name)
          name = vim.trim(name or "")
          if name ~= "" then vim.b[r.buf].term_name = name end
          m.refresh()
        end)
      end,
      x = function(r, m)
        if not (r and r.buf) then return end
        if vim.fn.confirm("Kill terminal " .. term.name(r.buf) .. "?", "&Kill\n&Cancel", 2) == 1 then
          term.kill(r.buf)
        end
        m.refresh()
      end,
    },
  })
end

return M
