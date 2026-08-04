-- Aggregates every plugin spec in this directory into one list for lazy.
-- Required explicitly by init.lua (not lazy's `import = "plugins"`): lazy
-- rebuilds the rtp at setup and would drop a prepended config dir, while
-- package.path still resolves these requires.

local specs = {}
for _, name in ipairs({
  -- appearance
  "colorscheme",
  "devicons",
  "bufferline",
  "lualine",
  "virt-column",
  "showkeys",
  -- languages & editing
  "treesitter",
  "twig",
  "lsp",
  "lint",
  -- navigation
  "nvim-tree",
  "telescope",
  -- git
  "gitsigns",
  "blame",
  "diffview",
  "git-conflict",
  -- extras
  "vim-be-good",
  "leetcode",
}) do
  specs[#specs + 1] = require("plugins." .. name)
end

return specs
