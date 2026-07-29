return {
  -- PHPStan diagnostics, but only when the project actually ships it.
  -- Walks up from the current file to a repo root; if vendor/bin/phpstan
  -- exists there, it runs against that repo's phpstan.neon (level 7 etc.)
  -- and shows the warnings inline. In a source-only checkout with no
  -- vendor/, it's a silent no-op -- nothing to configure per project.
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufWritePost" },
  config = function()
    local lint = require("lint")
    lint.linters_by_ft = { php = { "phpstan" } }

    -- Nearest ancestor dir that actually has a runnable phpstan binary.
    local function phpstan_at(bufnr)
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "" then return nil end
      local root = vim.fs.root(bufnr, {
        "phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon",
        "composer.json", ".git",
      })
      if not root then return nil end
      local bin = root .. "/vendor/bin/phpstan"
      if (vim.uv or vim.loop).fs_stat(bin) then
        return bin, root
      end
      return nil
    end

    local function run_phpstan()
      if vim.bo.filetype ~= "php" then return end
      local bin, root = phpstan_at(0)
      if not bin then return end            -- guard: no phpstan → do nothing
      lint.linters.phpstan.cmd = bin
      lint.linters.phpstan.cwd = root       -- run from root so phpstan.neon is found
      lint.try_lint("phpstan")
    end

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
      callback = run_phpstan,
    })
    vim.schedule(run_phpstan)  -- lint the buffer that triggered the load
  end,
}
