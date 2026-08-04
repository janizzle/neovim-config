-- Entry point: leader keys, make lua/ require()-able, bootstrap lazy.nvim,
-- then hand off to config/ and plugins/.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Make lua/ require()-able even when launched with `-u <dir>/init.lua`, which
-- puts the file on the command line but not its parent on the runtime path.
local this_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
package.path = this_dir .. "/lua/?.lua;" .. this_dir .. "/lua/?/init.lua;" .. package.path
vim.opt.rtp:prepend(this_dir)

require("config.options")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Required directly rather than via lazy's `import = "plugins"`: lazy rebuilds
-- the rtp at setup and drops our prepended dir; package.path still resolves.
require("lazy").setup(require("plugins"))

require("config.ui")
require("config.keymaps")
require("config.blame")
require("config.layout")
require("config.php")
