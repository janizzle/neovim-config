return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "lua", "vim", "vimdoc", "bash",
        "php", "phpdoc",
        "html", "css", "scss",
        "javascript", "typescript", "tsx",
        "json", "yaml", "toml", "markdown", "markdown_inline",
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
        -- Twig (ft=html.twig) stays on vim-twig's regex syntax so the
        -- {{ }} / {% %} internals get colored; the html parser would win
        -- otherwise and leave them plain.
        disable = function(_, buf)
          return vim.bo[buf].filetype == "html.twig"
        end,
      },
      -- The pinned master-branch indent queries misfire on nvim 0.12 for
      -- javascript (indentexpr returns 0 -> every <CR> lands at column 0;
      -- typescript/tsx share the query family) and for html driving Twig
      -- (wrong levels). Disabled there so the runtime indent scripts take
      -- over (GetJavascriptIndent / HtmlIndent + after/indent/twig.lua).
      -- php treesitter indent works and stays on.
      indent = {
        enable = true,
        disable = function(lang, buf)
          local broken = { javascript = true, typescript = true, tsx = true, html = true }
          return broken[lang] or vim.bo[buf].filetype == "html.twig"
        end,
      },
    })

    -- nvim 0.12 made a query match capture a LIST of nodes (TSNode[]); this
    -- pinned nvim-treesitter still passes match[id] to single-node APIs,
    -- which throws "attempt to call method 'range'". Two hotfixes:

    -- 1. Injection path: core's LanguageTree hands vim.treesitter.get_range a
    --    list capture -- crashed Telescope previews of injection-bearing
    --    files (PHP+HTML, markdown). Collapse a list to its first node.
    if not vim.treesitter._get_range_orig then
      vim.treesitter._get_range_orig = vim.treesitter.get_range
      vim.treesitter.get_range = function(node, source, metadata)
        if type(node) == "table" and node[1] ~= nil and node.range == nil then
          node = node[1]
        end
        return vim.treesitter._get_range_orig(node, source, metadata)
      end
    end

    -- 2. Markdown fenced-code directives -- fired on every LSP hover float
    --    and tore down the highlighter. Re-register them list-safe.
    local query = vim.treesitter.query
    local function first_node(n)
      if type(n) == "table" and n[1] ~= nil then return n[1] end
      return n
    end
    query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
      local node = first_node(match[pred[2]])
      if not node then return end
      local alias = vim.treesitter.get_node_text(node, bufnr):lower()
      local ok, mod = pcall(require, "nvim-treesitter.parsers")
      local lang = alias
      if ok and mod.ft_to_lang then lang = mod.ft_to_lang(alias) or alias end
      metadata["injection.language"] = lang
    end, { force = true, all = false })
    query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
      local node = first_node(match[pred[2]])
      if not node then return end
      local mime = vim.treesitter.get_node_text(node, bufnr)
      local parts = vim.split(mime, "/", {})
      metadata["injection.language"] = parts[#parts]
    end, { force = true, all = false })
  end,
}
