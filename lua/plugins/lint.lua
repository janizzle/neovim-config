return {
  -- PHPStan diagnostics, only when the project ships it: runs the repo's own
  -- vendor/bin/phpstan against its phpstan.neon; silent no-op without one.
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufWritePost" },
  config = function()
    local lint = require("lint")
    lint.linters_by_ft = { php = { "phpstan" } }

    -- Nearest ancestor with a runnable phpstan binary.
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
      if not bin then return end
      lint.linters.phpstan.cmd = bin
      lint.linters.phpstan.cwd = root   -- so phpstan.neon is found
      lint.try_lint("phpstan")
    end

    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
      callback = run_phpstan,
    })
    vim.schedule(run_phpstan)  -- lint the buffer that triggered the lazy load
  end,
}
