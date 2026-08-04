return {
  -- LSP: intelephense (PHP) + ts_ls (JS/TS), installed by mason.
  "neovim/nvim-lspconfig",
  dependencies = {
    { "mason-org/mason.nvim", opts = {} },
    { "mason-org/mason-lspconfig.nvim" },
  },
  config = function()
    require("mason").setup()
    require("mason-lspconfig").setup({
      ensure_installed = { "intelephense", "ts_ls" },
    })

    -- Resolve a server binary: mason's install dir first, then $PATH, then
    -- the bare name. nvim-lspconfig's bundled cmds are bare names, and the
    -- current mason-org split no longer rewrites them to mason's absolute
    -- path -- on a machine where the binary is mason-only (WSL) the client
    -- then silently never starts and gd/gr fall back to keyword jumps.
    local function mason_bin(name)
      return vim.fn.stdpath("data") .. "/mason/bin/" .. name
    end
    local function server_cmd(name)
      local bin = mason_bin(name)
      if (vim.uv or vim.loop).fs_stat(bin) then return bin end
      local on_path = vim.fn.exepath(name)
      return on_path ~= "" and on_path or name
    end

    vim.lsp.config("intelephense", {
      cmd = { server_cmd("intelephense"), "--stdio" },
      -- Anchor a workspace even without composer.json/.git (source-only
      -- checkout); single-file mode can't resolve cross-file gd.
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, {
          "composer.json", ".git", "phpstan.neon", "phpstan.neon.dist",
        })
        on_dir(root or (vim.uv or vim.loop).cwd())
      end,
      settings = {
        intelephense = {
          -- Intelephense's full default stub list PLUS "gettext" (defines the
          -- _() translation alias). Must be explicit: setting "stubs" at all
          -- REPLACES the default set, so omissions go dark.
          stubs = {
            "apache", "bcmath", "bz2", "calendar", "com_dotnet", "Core",
            "ctype", "curl", "date", "dba", "dom", "enchant", "exif",
            "fileinfo", "filter", "fpm", "ftp", "gd", "gettext", "gmp",
            "hash", "iconv", "imap", "intl", "json", "ldap", "libxml",
            "mbstring", "meta", "mysqli", "oci8", "odbc", "openssl", "pcntl",
            "pcre", "PDO", "pdo_ibm", "pdo_mysql", "pdo_pgsql", "pdo_sqlite",
            "pgsql", "Phar", "posix", "pspell", "readline", "Reflection",
            "session", "shmop", "SimpleXML", "snmp", "soap", "sockets",
            "sodium", "SPL", "sqlite3", "standard", "superglobals", "sysvmsg",
            "sysvsem", "sysvshm", "tidy", "tokenizer", "xml", "xmlreader",
            "xmlrpc", "xmlwriter", "xsl", "Zend OPcache", "zip", "zlib",
          },
          files = {
            maxSize = 5000000,
            -- .direnv/ holds flake-input symlinks into /nix/store, some of
            -- which contain PHP -- indexed, every gd offered the real result
            -- plus its Nix copy. Keep the duplicates out of the index.
            exclude = {
              "**/.git/**",
              "**/.direnv/**",
              "**/node_modules/**",
              "**/vendor/**/{Tests,tests}/**",
              "/nix/store/**",
              "**/nix/store/**",
            },
          },
        },
      },
    })

    vim.lsp.config("ts_ls", {
      cmd = { server_cmd("typescript-language-server"), "--stdio" },
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, {
          "package.json", "tsconfig.json", "jsconfig.json", ".git",
        })
        on_dir(root or (vim.uv or vim.loop).cwd())
      end,
    })

    -- vim.lsp.config() only registers; without enable() no client starts,
    -- LspAttach never fires and the maps below never bind (nvim 0.11+).
    vim.lsp.enable("intelephense")
    vim.lsp.enable("ts_ls")

    -- Fresh machine: mason installs asynchronously. If the binary lands after
    -- a matching buffer already opened, re-point cmd at it and re-fire
    -- FileType so the client attaches without a restart.
    local function reattach_on_install(pkg, lsp_name, fts)
      local ok, registry = pcall(require, "mason-registry")
      if not ok or not registry.has_package(pkg) or registry.is_installed(pkg) then
        return
      end
      registry.get_package(pkg):once("install:success", function()
        vim.schedule(function()
          vim.lsp.config(lsp_name, { cmd = { mason_bin(pkg), "--stdio" } })
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.tbl_contains(fts, vim.bo[buf].filetype) then
              vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
            end
          end
        end)
      end)
    end
    reattach_on_install("intelephense", "intelephense", { "php" })
    reattach_on_install("typescript-language-server", "ts_ls",
      { "javascript", "javascriptreact", "typescript", "typescriptreact" })

    -- An exclude change only affects a FRESH index; this restarts the server
    -- with clearCache once so the index rebuilds without the Nix duplicates,
    -- then reverts so normal launches keep the fast cached index.
    vim.api.nvim_create_user_command("IntelephenseClearCache", function()
      for _, c in ipairs(vim.lsp.get_clients({ name = "intelephense" })) do
        vim.lsp.stop_client(c.id, true)
      end
      vim.lsp.config("intelephense", { init_options = { clearCache = true } })
      vim.schedule(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[buf].filetype == "php" then
            vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
          end
        end
        vim.lsp.config("intelephense", { init_options = { clearCache = false } })
        vim.notify("Intelephense: cache cleared, reindexing without .direnv/nix")
      end)
    end, { desc = "Rebuild Intelephense index (drops Nix duplicates)" })

    vim.diagnostic.config({
      virtual_text = true,
      severity_sort = true,
      float = { border = "rounded", source = true },
    })

    local hover_opts = {
      border = "rounded",
      max_width = 90,
      max_height = 25,
    }

    -- Smart K: on a line with diagnostics, one float with the full error
    -- message(s) on top and the LSP hover docs below; plain hover otherwise.
    local function smart_hover()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local diags = vim.diagnostic.get(0, { lnum = line })
      if #diags == 0 then
        vim.lsp.buf.hover(hover_opts)
        return
      end

      local severity_name = { "ERROR", "WARN", "INFO", "HINT" }
      local function build_diag_lines()
        local out = {}
        for _, d in ipairs(diags) do
          local sev = severity_name[d.severity] or "MSG"
          local src = d.source and (" [" .. d.source .. "]") or ""
          out[#out + 1] = "**" .. sev .. src .. "**"
          for _, msg_line in ipairs(vim.split(d.message, "\n", { plain = true })) do
            out[#out + 1] = msg_line
          end
          out[#out + 1] = ""
        end
        return out
      end

      local params = vim.lsp.util.make_position_params(0, "utf-16")
      vim.lsp.buf_request(0, "textDocument/hover", params, function(_, result)
        local lines = build_diag_lines()
        local hover_md = result and result.contents
          and vim.lsp.util.convert_input_to_markdown_lines(result.contents)
          or {}
        if #hover_md > 0 then
          lines[#lines + 1] = "---"
          for _, l in ipairs(hover_md) do lines[#lines + 1] = l end
        end
        while lines[#lines] == "" do lines[#lines] = nil end
        vim.lsp.util.open_floating_preview(lines, "markdown", {
          border = hover_opts.border,
          max_width = hover_opts.max_width,
          max_height = hover_opts.max_height,
          focus_id = "smart_hover",
          wrap = true,
        })
      end)
    end

    -- Buffer-local navigation keys, active once a server attaches.
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(ev)
        local buf = ev.buf
        local function map(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
        end
        local tb = require("telescope.builtin")

        map("gd", vim.lsp.buf.definition,        "LSP: go to definition")
        map("gD", vim.lsp.buf.declaration,       "LSP: go to declaration")
        map("gi", vim.lsp.buf.implementation,    "LSP: go to implementation")
        map("gy", vim.lsp.buf.type_definition,   "LSP: go to type definition")
        -- Full-size Telescope picker; selection routes into the main window
        -- (never the blame column).
        map("gr", function()
          tb.lsp_references({
            attach_mappings = require("config.picker").open_in_main,
            include_declaration = false,
          })
        end, "LSP: find references")
        map("K",  smart_hover, "LSP: hover docs (+ full error on diagnostic lines)")
        map("<leader>rn", vim.lsp.buf.rename,     "LSP: rename symbol")
        map("<leader>ca", vim.lsp.buf.code_action,"LSP: code action")
        map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "Prev diagnostic")
        map("]d", function() vim.diagnostic.jump({ count = 1 })  end, "Next diagnostic")
      end,
    })
  end,
}
