return {
  -- Formatting with the project's own tools only (vendor/bin, node_modules),
  -- like lint.lua's phpstan: a repo without a formatter never gets rewritten
  -- in a style it doesn't use. Formats on save when the project ships one;
  -- <leader>cf also falls back to the LSP's formatter.
  "stevearc/conform.nvim",
  event = "BufWritePre",
  cmd = "ConformInfo",
  keys = {
    {
      "<leader>cf",
      function() require("conform").format({ lsp_format = "fallback" }) end,
      mode = { "n", "v" },
      desc = "Format buffer / selection",
    },
  },
  config = function()
    -- conform resolves vendor/bin / node_modules/.bin upward and otherwise
    -- falls back to a global binary of the same name; only a project-local
    -- hit (an absolute path) counts as available here.
    local function project_local(self, ctx)
      local cmd = type(self.command) == "function" and self.command(self, ctx) or self.command
      return vim.startswith(cmd, "/")
    end

    local prettier = { "prettier" }
    require("conform").setup({
      formatters_by_ft = {
        php = { "pint", "php_cs_fixer", stop_after_first = true },
        javascript = prettier, javascriptreact = prettier,
        typescript = prettier, typescriptreact = prettier,
        css = prettier, scss = prettier, html = prettier,
        json = prettier, yaml = prettier, markdown = prettier,
      },
      formatters = {
        pint = { condition = project_local },
        php_cs_fixer = { condition = project_local },
        prettier = { condition = project_local },
      },
      -- quiet: no "formatters unavailable" warning in repos without one.
      format_on_save = { timeout_ms = 3000, lsp_format = "never", quiet = true },
    })
  end,
}
