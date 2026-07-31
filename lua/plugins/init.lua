-- Aggregates every plugin spec in this directory into one list for lazy.
-- Required explicitly by init.lua (rather than lazy's `import = "plugins"`)
-- because lazy rebuilds the runtimepath at setup and drops the .nvim-fix dir
-- we prepend, so an rtp-based import can't find these files -- but our
-- package.path entry still resolves `require("plugins.<name>")` fine.

local specs = {}
for _, name in ipairs({
  "colorscheme",
  "devicons",
  "showkeys",
  "treesitter",
  "twig",
  "lsp",
  "lint",
  "nvim-tree",
  "bufferline",
  "lualine",
  "telescope",
  "gitsigns",
  "blame",
  "diffview",
  "git-conflict",
  "virt-column",
  "vim-be-good",
  "leetcode",
}) do
  specs[#specs + 1] = require("plugins." .. name)
end

return specs
