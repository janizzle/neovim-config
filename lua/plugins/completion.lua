return {
  -- Completion popup: LSP, paths, snippets, buffer words, plus signature help
  -- while typing arguments. Loaded eagerly: requiring it advertises completion
  -- capabilities to every server through vim.lsp.config("*"), and a client
  -- started before that would never offer snippets or auto-imports.
  "saghen/blink.cmp",
  version = "1.*",   -- release tags ship the prebuilt fuzzy matcher
  opts = {
    -- <CR> accepts, <C-space> opens, <C-n>/<C-p> or arrows move.
    keymap = { preset = "enter" },
    completion = {
      menu = { border = "rounded" },
      documentation = { auto_show = true, window = { border = "rounded" } },
    },
    signature = { enabled = true, window = { border = "rounded" } },
  },
}
