-- Global vim options and a couple of feature flags. Loaded before lazy so the
-- flags (nerd font, netrw disable) are set by the time plugins configure.

-- Tell plugins (nvim-tree, telescope, ...) a Nerd Font is available so they
-- render glyph icons instead of ASCII fallbacks. This requires the TERMINAL
-- to actually use a Nerd Font (e.g. "JetBrainsMono Nerd Font", "FiraCode
-- Nerd Font"). If icons still show as boxes/? after this, set your terminal
-- font to a Nerd Font -- that part can't be fixed from inside Neovim.
vim.g.have_nerd_font = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.termguicolors = true
-- number + relativenumber together = "hybrid" gutter: every line shows its
-- distance from the cursor, EXCEPT the cursor line itself, which shows its
-- absolute number instead.
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.showtabline = 2
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.colorcolumn = ""      -- the line-length rule is drawn thin by virt-column.nvim
