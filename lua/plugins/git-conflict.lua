return {
  -- Inline, single-file conflict resolution: co / ct / cb / c0 to resolve,
  -- cn / cp to jump next / prev conflict. Buffer-local to conflicted files.
  "akinsho/git-conflict.nvim",
  version = "*",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    -- cn/cp (not the default ]x/[x): ] and [ need AltGr on a Swiss QWERTZ
    -- keyboard, whereas cn/cp share the same c-prefix as the resolve keys.
    default_mappings = {
      ours   = "co",
      theirs = "ct",
      none   = "c0",
      both   = "cb",
      next   = "cn",
      prev   = "cp",
    },
    default_commands   = true,   -- :GitConflictListQf, :GitConflictNextConflict, ...
    disable_diagnostics = false,
    list_opener        = "copen",
    -- Conflict region backgrounds: keep them subtle/transparent so the code
    -- underneath stays readable. current (ours) = blue tint, incoming
    -- (theirs) = magenta tint. See GitConflict* overrides in config/ui.lua
    -- (git-conflict defines these groups, we recolor them).
    highlights = {
      current  = "GitConflictCurrent",
      incoming = "GitConflictIncoming",
    },
  },
}
