-- Tiny shared slot for picker behaviour that both plugins/telescope.lua and
-- plugins/lsp.lua need.
--
-- telescope.lua owns the real implementation (it's the one with the actions /
-- window-routing helpers in scope) and assigns `open_in_main` here at config
-- time; lsp.lua reads it when `gr` fires. A module rather than a global so it
-- follows the same require() pattern as the rest of lua/config/.
--
-- lsp.lua must tolerate this being nil: LspAttach can fire before telescope's
-- config() has run, in which case `gr` just falls back to the plain picker.

return {
  open_in_main = nil,
}
