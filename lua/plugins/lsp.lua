return {
  -- LSP: code navigation (go-to-definition, references, hover, rename).
  -- mason installs the Intelephense server binary automatically on first run.
  "neovim/nvim-lspconfig",
  dependencies = {
    { "mason-org/mason.nvim", opts = {} },
    { "mason-org/mason-lspconfig.nvim" },
  },
  config = function()
    require("mason").setup()
    require("mason-lspconfig").setup({
      -- intelephense = PHP; ts_ls = JavaScript/TypeScript. ts_ls is what makes
      -- gd/gr work in .js files: without a JS server, `gd` fell back to Vim's
      -- builtin keyword jump, which only lands on the local `import` line and
      -- never crosses into the file the symbol is actually defined in.
      ensure_installed = { "intelephense", "ts_ls" },
    })

    -- Resolve the intelephense executable. nvim-lspconfig's bundled default
    -- is `cmd = { "intelephense", "--stdio" }` -- a BARE command that must be
    -- on $PATH. On macOS this "just worked" because intelephense was present
    -- globally (npm i -g). On WSL it's installed by mason to
    -- ~/.local/share/nvim/mason/bin/intelephense, and the current mason-org
    -- split no longer rewrites cmd to that absolute path -- so nvim tried to
    -- spawn bare `intelephense`, PATH lookup failed, no client started,
    -- LspAttach never fired, and gd fell back to Vim's builtin word search.
    -- Point cmd at mason's binary explicitly, falling back to $PATH.
    local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/intelephense"
    local intelephense_cmd = (vim.uv or vim.loop).fs_stat(mason_bin)
      and mason_bin
      or (vim.fn.exepath("intelephense") ~= "" and vim.fn.exepath("intelephense"))
      or "intelephense"  -- last resort: let PATH resolve at spawn time

    -- Intelephense tuning for a large ERP codebase.
    vim.lsp.config("intelephense", {
      cmd = { intelephense_cmd, "--stdio" },
      -- Anchor a workspace even when there's no composer.json / .git
      -- (e.g. a source-only checkout). Without a root, Intelephense runs
      -- single-file and cross-file `gd` can't see sibling classes. Fall
      -- back to nvim's cwd so it indexes the whole project you opened.
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, {
          "composer.json", ".git", "phpstan.neon", "phpstan.neon.dist",
        })
        on_dir(root or (vim.uv or vim.loop).cwd())
      end,
      settings = {
        intelephense = {
          -- PHP extension stubs Intelephense should treat as available.
          -- This is its full built-in default list PLUS "gettext" -- the
          -- extension that defines the _() translation alias (and gettext(),
          -- textdomain(), ...). Without the gettext stub, Intelephense flags
          -- every _() call as an undefined function. The list must be
          -- explicit: once "stubs" is set it REPLACES the default set rather
          -- than extending it, so any omitted extension would go dark.
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
            -- Keep the Nix duplicates out of the workspace index. .direnv/
            -- holds flake-inputs/*-source symlinks into /nix/store, and some
            -- of those Nix sources contain PHP -- so Intelephense follows the
            -- links and indexes a SECOND copy of the code, making every gd
            -- offer two results (the real src/ one + its Nix copy). Excluding
            -- .direnv (plus the store directly, for safety) leaves only the
            -- real project source.
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

    -- JavaScript / TypeScript server (ts_ls). Same mason-path story as
    -- intelephense: on WSL the binary is installed under mason, not on $PATH,
    -- so point cmd at it explicitly (falling back to $PATH) or the client
    -- never starts and gd/gr silently fall back to the builtin keyword jump.
    local ts_mason = vim.fn.stdpath("data") .. "/mason/bin/typescript-language-server"
    local ts_cmd = (vim.uv or vim.loop).fs_stat(ts_mason)
      and ts_mason
      or (vim.fn.exepath("typescript-language-server") ~= ""
        and vim.fn.exepath("typescript-language-server"))
      or "typescript-language-server"
    vim.lsp.config("ts_ls", {
      cmd = { ts_cmd, "--stdio" },
      -- Anchor a project root so cross-file "go to definition" resolves into
      -- the defining module instead of stopping at the local import. Fall back
      -- to nvim's cwd for a source-only checkout with no package.json/.git.
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, {
          "package.json", "tsconfig.json", "jsconfig.json", ".git",
        })
        on_dir(root or (vim.uv or vim.loop).cwd())
      end,
    })

    -- vim.lsp.config() only registers the config; the client won't start
    -- (and LspAttach won't fire, so gd/gr/K below never get bound) until the
    -- server is explicitly enabled. Required on nvim 0.11+/0.12.
    vim.lsp.enable("intelephense")
    vim.lsp.enable("ts_ls")

    -- An exclude change only affects a FRESH index -- the old workspace cache
    -- still holds the Nix duplicates. Run :IntelephenseClearCache once after
    -- adding the exclude: it restarts the server with clearCache set so the
    -- index is rebuilt from scratch (this time without .direnv/nix), then
    -- reverts so normal launches keep the fast cached index.
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
        -- Drop the flag so the next start reuses the rebuilt cache.
        vim.lsp.config("intelephense", { init_options = { clearCache = false } })
        vim.notify("Intelephense: cache cleared, reindexing without .direnv/nix")
      end)
    end, { desc = "Rebuild Intelephense index (drops Nix duplicates)" })

    -- On a FRESH machine (WSL first-run) mason downloads the intelephense
    -- binary asynchronously. If that finishes AFTER the PHP buffer opened,
    -- the mason_bin path above didn't exist yet, so cmd fell back to bare
    -- `intelephense` (or nothing). Once the install completes, re-point cmd
    -- at the now-present binary and re-fire FileType so it attaches without a
    -- restart.
    local function reattach_php()
      vim.lsp.config("intelephense", { cmd = { mason_bin, "--stdio" } })
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "php" then
          vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
        end
      end
    end
    local ok, registry = pcall(require, "mason-registry")
    if ok and registry.has_package("intelephense")
      and not registry.is_installed("intelephense")
    then
      registry.get_package("intelephense"):once("install:success", function()
        vim.schedule(reattach_php)
      end)
    end

    -- Same first-run reattach for ts_ls: if the JS/TS server finishes
    -- downloading after a .js buffer is already open, re-point cmd at the
    -- installed binary and re-fire FileType so gd/gr start working without a
    -- restart.
    local function reattach_js()
      vim.lsp.config("ts_ls", { cmd = { ts_mason, "--stdio" } })
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local ft = vim.bo[buf].filetype
        if ft == "javascript" or ft == "javascriptreact"
          or ft == "typescript" or ft == "typescriptreact"
        then
          vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
        end
      end
    end
    if ok and registry.has_package("typescript-language-server")
      and not registry.is_installed("typescript-language-server")
    then
      registry.get_package("typescript-language-server"):once("install:success", function()
        vim.schedule(reattach_js)
      end)
    end

    -- Slightly nicer diagnostic display.
    vim.diagnostic.config({
      virtual_text = true,
      severity_sort = true,
      float = { border = "rounded", source = true },
    })

    -- Hover float styling: rounded border + a sane max size so the K popup
    -- isn't a borderless, full-width slab. Reused by the K mapping below.
    local hover_opts = {
      border = "rounded",
      max_width = 90,
      max_height = 25,
    }

    -- Smart K: on a line that has a diagnostic (error/warning), show the full
    -- error message(s) at the TOP of the float and the LSP hover docs below,
    -- in one window. On a clean line, just the hover docs. Because we render
    -- both into a single markdown float ourselves, we first ask the server
    -- for the hover text, then prepend the diagnostics and open the popup.
    local function smart_hover()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local diags = vim.diagnostic.get(0, { lnum = line })

      -- No diagnostic on this line -> plain hover, nothing to combine.
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
        -- Drop a trailing blank so the float isn't padded at the bottom.
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
        -- References always as a full-size Telescope window (the layout comes
        -- from telescope.lua's `defaults`, so it no longer shrinks to whichever
        -- split happened to be focused), and selecting a result routes into the
        -- main window rather than possibly landing in the blame column.
        map("gr", function()
          tb.lsp_references({
            attach_mappings = require("config.picker").open_in_main,
            include_declaration = false,   -- the symbol itself isn't a "reference"
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
