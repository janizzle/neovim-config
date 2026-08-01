-- Entry point. Kept thin on purpose: it only sets leader keys, makes the
-- lua/ dir require()-able, bootstraps lazy.nvim, and then hands off to the
-- config/ and plugins/ modules. Everything with real content lives there.

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Make the lua/ dir sitting next to this init.lua require()-able, even when
-- nvim is launched with `-u .nvim-fix/init.lua` (that puts the file on the
-- command line but does NOT add its parent to the runtime path).
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

-- plugins/init.lua aggregates every spec in lua/plugins/ into one list.
-- (Required directly rather than via lazy's `import = "plugins"`: lazy rebuilds
-- the runtimepath at setup and drops the prepended .nvim-fix dir, so an
-- rtp-based import can't find them -- our package.path entry still can.)
require("lazy").setup(require("plugins"))

require("config.ui")
require("config.keymaps")
require("config.blame")
require("config.layout")
require("config.php")
