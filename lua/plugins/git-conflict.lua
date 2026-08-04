return {
  -- Inline conflict resolution: co/ct/cb/c0 to resolve, cn/cp to jump.
  "akinsho/git-conflict.nvim",
  version = "*",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    -- cn/cp instead of the default ]x/[x: brackets need AltGr on Swiss
    -- QWERTZ, and cn/cp share the c-prefix with the resolve keys.
    default_mappings = {
      ours   = "co",
      theirs = "ct",
      none   = "c0",
      both   = "cb",
      next   = "cn",
      prev   = "cp",
    },
    default_commands   = true,
    disable_diagnostics = false,
    list_opener        = "copen",
    -- Region groups recolored in config/ui.lua: ours = blue tint,
    -- theirs = magenta tint, subtle so the code stays readable.
    highlights = {
      current  = "GitConflictCurrent",
      incoming = "GitConflictIncoming",
    },
  },
}
