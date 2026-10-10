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

    -- Servers without import code actions (intelephense) still attach the
    -- `use` statement to completion items as additionalTextEdits. Ask for
    -- completions at the end of the word under the cursor, keep the items
    -- named exactly like it, and apply the chosen item's edits.
    local function import_via_completion(buf)
      local word = vim.fn.expand("<cword>")
      if word == "" then return end
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local endcol = col + #line:sub(col + 1):match("^[%w_]*")
      local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" })[1]
      if not client then
        vim.notify("No LSP completion available for import", vim.log.levels.WARN)
        return
      end
      local params = {
        textDocument = vim.lsp.util.make_text_document_params(buf),
        position = {
          line = row - 1,
          character = vim.str_utfindex(line, "utf-16", endcol, false),
        },
      }

      local function apply(item)
        local function done(it)
          vim.lsp.util.apply_text_edits(it.additionalTextEdits, buf, client.offset_encoding)
        end
        if item.additionalTextEdits and #item.additionalTextEdits > 0 then
          done(item)
        else
          client:request("completionItem/resolve", item, function(_, resolved)
            if resolved and resolved.additionalTextEdits and #resolved.additionalTextEdits > 0 then
              done(resolved)
            else
              vim.notify("No import available for " .. word, vim.log.levels.INFO)
            end
          end, buf)
        end
      end

      client:request("textDocument/completion", params, function(err, result)
        if err or not result then
          vim.notify("Import lookup failed", vim.log.levels.WARN)
          return
        end
        local items = result.items or result
        local matches, seen = {}, {}
        for _, it in ipairs(items) do
          local key = (it.detail or "") .. "\0" .. it.label
          if it.label:lower() == word:lower() and not seen[key] then
            seen[key] = true
            matches[#matches + 1] = it
          end
        end
        if #matches == 0 then
          vim.notify("No import found for " .. word, vim.log.levels.INFO)
        elseif #matches == 1 then
          apply(matches[1])
        else
          vim.ui.select(matches, {
            prompt = "Import " .. word,
            format_item = function(it) return it.detail or it.label end,
          }, function(choice) if choice then apply(choice) end end)
        end
      end, buf)
    end

    -- Sort imports. TS/JS: the server's source.organizeImports action. PHP
    -- (intelephense has none): each run of consecutive single-line top-level
    -- `use` statements is sorted -- classes, then functions, then consts --
    -- case-insensitively, dropping exact duplicates and imports whose name
    -- (or alias) appears nowhere else in the file. That's a text check, so a
    -- name mentioned only in a comment counts as used.
    local function sort_php_uses(buf)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local function rank(l)
        if l:match("^use%s+function%s") then return 1 end
        if l:match("^use%s+const%s") then return 2 end
        return 0
      end
      local function is_use(l) return l:match("^use%s+[^%(%s][^;{}]*;%s*$") ~= nil end
      local function before(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return a:lower() < b:lower()
      end

      -- Everything that isn't a plain import line: where a name must show up
      -- (code, docblocks, attributes, multi-line group imports) to count as used.
      local body = {}
      for _, l in ipairs(lines) do
        if not is_use(l) then body[#body + 1] = l end
      end
      local haystack = table.concat(body, "\n"):lower()

      local function used(l)
        local spec = l:gsub("^use%s+function%s+", ""):gsub("^use%s+const%s+", "")
          :gsub("^use%s+", ""):gsub("%s*;%s*$", "")
        local name = spec:match("%s+[aA][sS]%s+([%w_]+)$") or spec:match("([%w_]+)$")
        if not name then return true end
        return haystack:find("%f[%w_]" .. vim.pesc(name:lower()) .. "%f[^%w_]") ~= nil
      end

      local out, i = {}, 1
      while i <= #lines do
        if is_use(lines[i]) then
          local block, seen = {}, {}
          while i <= #lines and is_use(lines[i]) do
            if not seen[lines[i]] and used(lines[i]) then
              seen[lines[i]] = true
              block[#block + 1] = lines[i]
            end
            i = i + 1
          end
          table.sort(block, before)
          vim.list_extend(out, block)
        else
          out[#out + 1] = lines[i]
          i = i + 1
        end
      end

      if vim.deep_equal(out, lines) then return end
      local view = vim.fn.winsaveview()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
      vim.fn.winrestview(view)
    end

    local function sort_imports(buf)
      buf = buf or vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype == "php" then
        sort_php_uses(buf)
      else
        vim.lsp.buf.code_action({
          context = { only = { "source.organizeImports" }, diagnostics = {} },
          apply = true,
        })
      end
    end
    vim.api.nvim_create_user_command("SortImports", function() sort_imports() end,
      { desc = "Sort the buffer's imports" })

    -- Neovim 0.11+ ships global grr/gri/gra/grn/grt/grx (and gO). With them
    -- around, our `gr` is only a prefix: Neovim waits after it, and one extra
    -- key lands in grr/gri -- plain vim.lsp.buf calls that fill the quickfix
    -- window at the bottom instead of Telescope. Everything they do has its
    -- own key here (gr, gi, <leader>ca, <leader>rn, gy).
    for _, lhs in ipairs({ "grr", "gri", "grn", "grt", "grx" }) do
      pcall(vim.keymap.del, "n", lhs)
    end
    pcall(vim.keymap.del, { "n", "x" }, "gra")

    -- Buffer-local navigation keys, active once a server attaches.
    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(ev)
        local buf = ev.buf
        local function map(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
        end
        local tb = require("telescope.builtin")

        -- Every jump goes through Telescope: one result jumps straight there,
        -- several open the full-size picker, and a selection routes into the
        -- main window (never the blame column). vim.lsp.buf.definition & co.
        -- dump several results into the quickfix window at the bottom instead
        -- -- which is what gd did whenever a server answered twice (intelephense
        -- duplicates, a .d.ts next to the source).
        local function picker(fn, extra)
          return function()
            fn(vim.tbl_extend("force", {
              attach_mappings = require("config.picker").open_in_main,
            }, extra or {}))
          end
        end

        map("gd", picker(tb.lsp_definitions),      "LSP: go to definition")
        map("gD", vim.lsp.buf.declaration,         "LSP: go to declaration")
        map("gi", picker(tb.lsp_implementations),  "LSP: go to implementation")
        map("gy", picker(tb.lsp_type_definitions), "LSP: go to type definition")
        map("gr", picker(tb.lsp_references, { include_declaration = false }),
          "LSP: find references")
        map("K",  smart_hover, "LSP: hover docs (+ full error on diagnostic lines)")
        map("<leader>rn", vim.lsp.buf.rename,     "LSP: rename symbol")
        map("<leader>ca", vim.lsp.buf.code_action,"LSP: code action")
        -- Import menu for the symbol under the cursor: only the import-type
        -- code actions (ts_ls "Add import from ...", one entry per candidate).
        map("<leader>ci", function()
          if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/codeAction" }) > 0 then
            vim.lsp.buf.code_action({
              apply = false,
              filter = function(a) return a.title:lower():find("import", 1, true) ~= nil end,
            })
          else
            import_via_completion(buf)
          end
        end, "LSP: import symbol (pick namespace)")
        map("<leader>cs", function() sort_imports(buf) end, "LSP: sort imports")
        map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "Prev diagnostic")
        map("]d", function() vim.diagnostic.jump({ count = 1 })  end, "Next diagnostic")
      end,
    })
  end,
}
