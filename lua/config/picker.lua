-- Shared slot: telescope.lua assigns `open_in_main` (route picked files into
-- the main window) at config time; lsp.lua reads it for `gr` and must
-- tolerate nil, since LspAttach can fire before telescope's config runs.

return {
  open_in_main = nil,
}
