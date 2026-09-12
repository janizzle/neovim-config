return {
  -- LSP: every server listed in config/servers.lua, installed by mason.
  "neovim/nvim-lspconfig",
  dependencies = {
    { "mason-org/mason.nvim", opts = {} },
    { "mason-org/mason-lspconfig.nvim" },
    { "b0o/SchemaStore.nvim" },   -- json/yaml schemas, read by config/servers.lua
  },
  config = function()
    local mason = require("config.mason")
    local servers = require("config.servers")
    local names = vim.tbl_keys(servers)

    require("mason").setup()
    require("mason-lspconfig").setup({ ensure_installed = names })

    -- Point a table cmd at mason's binary. nvim-lspconfig's bundled cmds are
    -- bare names, and the current mason-org split no longer rewrites them to
    -- mason's absolute path -- on a machine where the binary is mason-only
    -- (WSL) the client then silently never starts and gd/gr fall back to
    -- keyword jumps. Function cmds (the vscode-* servers) resolve the
    -- project's node_modules/.bin first, then $PATH.
    local function resolve_cmd(name)
      local cmd = vim.lsp.config[name].cmd
      if type(cmd) ~= "table" then return end
      vim.lsp.config(name, { cmd = { mason.cmd(vim.fs.basename(cmd[1])), unpack(cmd, 2) } })
    end

    for name, opts in pairs(servers) do
      vim.lsp.config(name, opts)
      resolve_cmd(name)
    end

    -- vim.lsp.config() only registers; without enable() no client starts,
    -- LspAttach never fires and the maps below never bind (nvim 0.11+).
    vim.lsp.enable(names)

    -- Fresh machine: mason installs asynchronously. If a server lands after a
    -- matching buffer already opened, re-point cmd at it and re-fire FileType
    -- so the client attaches without a restart.
    local to_package = require("mason-lspconfig").get_mappings().lspconfig_to_package
    for _, name in ipairs(names) do
      mason.on_install(to_package[name], function()
        resolve_cmd(name)
        local fts = vim.lsp.config[name].filetypes or {}
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.tbl_contains(fts, vim.bo[buf].filetype) then
            vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
          end
        end
      end)
    end

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
