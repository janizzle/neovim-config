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
