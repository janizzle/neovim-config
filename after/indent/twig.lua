-- Twig-aware indent for ft=html.twig, sourced for the `twig` component after
-- $VIMRUNTIME/indent/html.vim and vim-twig's indent/twig.vim -- so it wins.
-- (vim-twig's own GetTwigIndent never survives its double-FileType load
-- order; html.vim's HtmlIndent was left in charge and knows nothing about
-- {% %} blocks.) Twig block tags are handled here, every other line is
-- delegated to HtmlIndent().

local OPEN = vim.regex([[{%-\?\s*\(if\|for\|block\|macro\|filter\|embed\|apply\|verbatim\|sandbox\|with\|trans\|autoescape\|cache\)\>]])
-- else/elseif sit at the opener's level and open one deeper.
local MID = vim.regex([[{%-\?\s*\(else\|elseif\)\>]])
local CLOSE = vim.regex([[{%-\?\s*end\w\+]])

local function has(re, line)
  return re:match_str(line) ~= nil
end

function _G.TwigIndent()
  local lnum = vim.v.lnum
  local prevlnum = vim.fn.prevnonblank(lnum - 1)
  if prevlnum == 0 then return 0 end

  local cur = vim.fn.getline(lnum)
  local prev = vim.fn.getline(prevlnum)
  local sw = vim.bo.shiftwidth ~= 0 and vim.bo.shiftwidth or vim.bo.tabstop

  -- {% endif %} / {% else %}: align with the matching opener. Lines that
  -- both open and close ({% if x %}...{% endif %} one-liners) are neutral.
  if (has(CLOSE, cur) and not has(OPEN, cur)) or has(MID, cur) then
    local depth = 0
    for l = lnum - 1, 1, -1 do
      local line = vim.fn.getline(l)
      local opens = has(OPEN, line) and not has(CLOSE, line)
      local closes = has(CLOSE, line) and not has(OPEN, line)
      if closes then
        depth = depth + 1
      elseif opens then
        if depth == 0 then return vim.fn.indent(l) end
        depth = depth - 1
      end
    end
    return math.max(vim.fn.indent(prevlnum) - sw, 0)
  end

  -- Previous line opened a block and didn't close it on the same line.
  if (has(OPEN, prev) or has(MID, prev)) and not has(CLOSE, prev) then
    return vim.fn.indent(prevlnum) + sw
  end

  if vim.fn.exists("*HtmlIndent") == 1 then
    return vim.fn.HtmlIndent()      -- reads v:lnum itself
  end
  return vim.fn.indent(prevlnum)
end

vim.bo.indentexpr = "v:lua.TwigIndent()"
-- Re-indent when `%}` completes a tag, so a typed {% endif %} / {% else %}
-- snaps back to its opener's level.
vim.bo.indentkeys = vim.bo.indentkeys .. ",=%}"
