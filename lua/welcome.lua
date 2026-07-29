-- Start screen painted into the empty scratch buffer on launch.
-- Split out of init.lua; wired up via require("welcome").paint(buf).

local M = {}

local lines = {
  "",
  "",
  "    ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
  "    ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
  "    ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
  "    ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
  "    ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
  "    ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
  "",
  "    ── Stock Neovim / plugin commands ──────────────────────────",
  "",
  "    gd gr K       Go to definition · references · hover (LSP)",
  "    gD gi gy      Declaration · implementation · type definition",
  "    [d ]d         Prev / next diagnostic",
  "    ]c [c         Prev / next changed hunk",
  "    co ct cb c0   Resolve conflict: ours · theirs · both · none",
  "    cn cp         Next / prev merge conflict",
  "    In file tree  a=new file  a…/=new folder  d=delete  r=rename",
  "    :qa           Quit all",
  "",
  "    ── My commands (space leader) ──────────────────────────────",
  "",
  "    Files & search",
  "      <space>ff   Find files          <space>fg   Live grep",
  "      <space>fw   Grep word           <space>fb   Switch buffers",
  "      <space>fd   Find directory      <space>fh   Help tags",
  "",
  "    Buffers & windows",
  "      <space>s    Save                <space>x    Save & close",
  "      <space>q    Force close         <space>X    Force close (discard)",
  "      <space>w1-9 Jump to window      <space>t1-9 Jump to buffer tab",
  "      Shift-h/l   Prev / next buffer tab",
  "      <space>l    Restore startup layout",
  "",
  "    Git changes",
  "      <space>gs   Git changed files   <space>gb   Blame column",
  "      <space>hp   Preview change (float)   <space>hi  Preview inline",
  "      <space>hb   Blame line          <space>hB   Toggle inline blame",
  "      <space>hs   Stage hunk          <space>hr   Reset hunk",
  "      <space>hS   Stage file          <space>hR   Reset file",
  "      <space>hw   Toggle word diff    <space>hL   Toggle line highlight",
  "      <space>cn   Next changed line   <space>cp   Prev changed line",
  "",
  "    Diff & conflicts",
  "      <space>dv   Working changes     <space>dc   Last commit",
  "      <space>dh   File history        <space>dH   Repo history",
  "      <space>dx   List conflicts (qf) <space>dq   Close diff",
  "",
  "    Code (LSP)",
  "      <space>rn   Rename symbol       <space>ca   Code action",
  "",
  "    ── Project commands ────────────────────────────────────────",
  "",
  "    Unit tests          phpunit -c phpunit-unit.xml",
  "    Integration tests   phpunit -c phpunit-integration.xml",
  "    Single test         phpunit -c phpunit-unit.xml --filter <name>",
  "    JS tests            npm run jstest   ·   coverage: npm run jstest-coverage",
  "    E2E tests           npx nightwatch",
  "    Static analysis     vendor/bin/phpstan analyse",
  "    Build assets        npm run build   ·   watch: npm run watch",
  "",
}

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
  vim.api.nvim_create_autocmd("InsertEnter", {
    buffer = buf,
    once = true,
    callback = function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.bo[buf].modified = false
    end,
  })
end

return M
