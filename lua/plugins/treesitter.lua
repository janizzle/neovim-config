return {
  "nvim-treesitter/nvim-treesitter",
  branch = "master",
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "lua", "vim", "vimdoc", "bash",
        -- php_only is the same grammar entered at the CODE rule instead of at
        -- the text/HTML rule. Needed for tag-less snippets (LeetCode solutions
        -- start straight at `class Solution`): see config/php.lua.
        "php", "php_only", "phpdoc",
        "html", "css", "scss",
        "javascript", "typescript", "tsx",
        "json", "yaml", "toml", "markdown", "markdown_inline",
      },
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
        -- Twig files (ft=html.twig) are driven by the vim-twig regex syntax
        -- (html + twig) instead of the html treesitter parser, so the
        -- {{ }} / {% %} internals actually get colored.
        disable = function(_, buf)
          return vim.bo[buf].filetype == "html.twig"
        end,
      },
      indent = { enable = true },
    })

    -- nvim 0.12 changed treesitter so a query match capture is a LIST of
    -- nodes (TSNode[]), not a single TSNode. This nvim-treesitter (master,
    -- Mar 2026) still passes match[id] straight to get_node_text(), which
    -- calls node:range() -- a list has no :range(), so it throws
    -- "attempt to call method 'range' (a nil value)". It fires on markdown
    -- fenced-code injections, i.e. every LSP hover float (K), which then
    -- tears down the highlighter and the buffer loses coloring. Re-register
    -- the two info-string directives to normalize the capture to one node.

    -- Same v0.12 list-vs-node regression, but on the INJECTION path core
    -- itself walks (LanguageTree:_parse -> get_range), which no directive
    -- covers: the async injection parse hands vim.treesitter.get_range a
    -- capture that is now a TSNode[] instead of a TSNode, and node:range()
    -- blows up inside a vim.schedule callback -- exactly the crash seen when
    -- previewing an injection-bearing file (PHP+HTML, markdown, ...) in the
    -- <leader>ff / <leader>gs Telescope previews. Wrap get_range once so any
    -- list capture is collapsed to its first node before :range() is called.
    if not vim.treesitter._get_range_orig then
      vim.treesitter._get_range_orig = vim.treesitter.get_range
      vim.treesitter.get_range = function(node, source, metadata)
        if type(node) == "table" and node[1] ~= nil and node.range == nil then
          node = node[1]
        end
        return vim.treesitter._get_range_orig(node, source, metadata)
      end
    end

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
