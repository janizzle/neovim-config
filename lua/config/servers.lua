-- Language servers: name -> vim.lsp.config() overrides layered on top of
-- nvim-lspconfig's bundled defaults. plugins/lsp.lua installs (mason),
-- configures and enables every entry, so adding a server is one line here.

local uv = vim.uv or vim.loop

-- Anchor a workspace even without a project marker (source-only checkout);
-- single-file mode can't resolve cross-file gd.
local function root_or_cwd(markers)
  return function(bufnr, on_dir)
    on_dir(vim.fs.root(bufnr, markers) or uv.cwd())
  end
end

return {
  intelephense = {
    root_dir = root_or_cwd({ "composer.json", ".git", "phpstan.neon", "phpstan.neon.dist" }),
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
  },

  ts_ls = {
    -- Table form (the bundled cmd is a function), so plugins/lsp.lua can
    -- resolve it to mason's binary.
    cmd = { "typescript-language-server", "--stdio" },
    root_dir = root_or_cwd({ "package.json", "tsconfig.json", "jsconfig.json", ".git" }),
  },

  html = {},
  cssls = {},
  eslint = {},   -- only starts where the project has an eslint config

  jsonls = {
    settings = {
      json = { schemas = require("schemastore").json.schemas(), validate = { enable = true } },
    },
  },

  yamlls = {
    settings = {
      yaml = {
        -- SchemaStore.nvim's catalog replaces the server's own download.
        schemaStore = { enable = false, url = "" },
        schemas = require("schemastore").yaml.schemas(),
      },
    },
  },

  -- Only in projects that install tailwind: the bundled root falls back to
  -- .git, which would start it for every PHP/HTML buffer in any repo.
  tailwindcss = {
    root_dir = function(bufnr, on_dir)
      local root = vim.fs.root(bufnr, "node_modules")
      if root and uv.fs_stat(root .. "/node_modules/tailwindcss") then
        on_dir(root)
      end
    end,
  },

  -- vim-twig sets ft=html.twig; the bundled config only lists "twig". The
  -- server fails initialize without a workspace folder, hence the cwd fallback.
  twiggy_language_server = {
    root_dir = root_or_cwd({ "composer.json", ".git" }),
    filetypes = { "twig", "html.twig" },
    get_language_id = function() return "twig" end,
  },
}
