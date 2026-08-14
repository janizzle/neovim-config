-- Global options and feature flags. Loaded before lazy so plugins see them.

vim.g.have_nerd_font = true    -- glyph icons; requires a Nerd Font terminal font
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.termguicolors = true
vim.opt.number = true
vim.opt.relativenumber = true  -- hybrid gutter: absolute on the cursor line, relative elsewhere
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.showtabline = 2
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.colorcolumn = ""       -- line-length rule drawn thin by virt-column.nvim

-- Visible whitespace: middle dot per space, return symbol at each line break.
-- Colored dim via Whitespace / NonText in plugins/colorscheme.lua.
vim.opt.list = true
vim.opt.listchars = {
  space    = "·",
  trail    = "·",
  tab      = "» ",
  eol      = "↵",
  nbsp     = "␣",
  extends  = "›",
  precedes = "‹",
}

-- `list` is window-local, so it would stick to a window after a tree/panel
-- buffer leaves it -- and dots all over the welcome banner or the file tree are
-- just noise. Normalize it every time a buffer is displayed in a window.
local no_list_ft = {
  NvimTree = true, TelescopePrompt = true, TelescopeResults = true,
  DiffviewFiles = true, DiffviewFileHistory = true, MergeConflicts = true,
  help = true, lazy = true, mason = true, qf = true, blame = true,
  checkhealth = true, showkeys = true,
}

vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType", "TermOpen" }, {
  callback = function(ev)
    local buf = ev.buf
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local hide = vim.b[buf].welcome_screen
      or no_list_ft[vim.bo[buf].filetype]
      or vim.bo[buf].buftype == "terminal"
      or vim.bo[buf].buftype == "nofile"
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        -- Never in a diff: three narrow panes of dotted spaces and trailing
        -- return arrows bury the thing you opened the diff to read.
        vim.wo[win].list = not (hide or vim.wo[win].diff)
      end
    end
  end,
})
