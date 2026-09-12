return {
  -- Structure view: the current file's classes / methods / functions in a
  -- panel on the right (<leader>o). Also feeds the breadcrumb path in lualine.
  "stevearc/aerial.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
  config = function()
    require("aerial").setup({
      -- Server symbols first: intelephense / ts_ls know the language better
      -- than the parser queries; treesitter covers files with no server.
      backends = { "lsp", "treesitter", "markdown" },
    })
    vim.keymap.set("n", "<leader>o", "<cmd>AerialToggle<cr>", { desc = "Structure view (toggle)" })
  end,
}
