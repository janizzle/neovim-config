-- UI chrome recoloring that isn't tied to a single plugin's config: the diff
-- backgrounds and the global blue+magenta accent scheme. Both are reapplied on
-- ColorScheme so they survive theme reloads.

-- Nicer, less washed-out diff colors (darcula's DiffChange is a muddy grey and
-- DiffDelete has no background).
local function improve_diff_colors()
  vim.api.nvim_set_hl(0, "DiffAdd",    { bg = "#20402a", fg = "NONE" })  -- added / OURS side
  vim.api.nvim_set_hl(0, "DiffChange", { bg = "#25314a", fg = "NONE" })  -- changed line (context)
  vim.api.nvim_set_hl(0, "DiffText",   { bg = "#3a5279", fg = "NONE", bold = true })  -- exact changed chars
  vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#4a2530", fg = "#7a3b48" })  -- removed / THEIRS side
end
improve_diff_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_diff_colors })

-- Recolor the neovim UI chrome to a blue + magenta accent scheme. This ONLY
-- touches interface elements (borders, selections, statusline/bufferline
-- accents, popup-menu selection, matched brackets, search, conflict regions):
-- window backgrounds, icon colors, code syntax coloring and the diff-view
-- backgrounds are deliberately left untouched. Backgrounds are kept transparent
-- (NONE) or a faint tint so code underneath stays readable.
local function improve_ui_colors()
  local hl   = vim.api.nvim_set_hl
  local blue = "#61AFEF"
  local mag  = "#c264c9"
  -- Same purple the palette uses for variables/identifiers, reused here so the
  -- cursor line number reads as part of the existing accent set.
  local purple = "#C678DD"
  -- faint tints (used only where a background genuinely helps legibility)
  local blue_bg = "#22384f"
  local mag_bg  = "#3a2740"

  -- Selection / search / cursor accents.
  hl(0, "Visual",        { bg = blue_bg })
  hl(0, "VisualNOS",     { bg = blue_bg })
  hl(0, "Search",        { fg = "NONE", bg = mag_bg })
  hl(0, "IncSearch",     { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "CurSearch",     { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "MatchParen",    { fg = mag, bold = true, bg = "NONE" })

  -- Floating-window borders (window separators / VertSplit left at the theme
  -- default so the window divide line keeps its original color).
  hl(0, "FloatBorder",   { fg = blue, bg = "NONE" })
  hl(0, "FloatTitle",    { fg = mag, bold = true, bg = "NONE" })

  -- Popup / completion menu: transparent rows, blue selection, magenta scrollbar.
  hl(0, "Pmenu",         { fg = "#A9B7C6", bg = "#3C3F41" })
  hl(0, "PmenuSel",      { fg = "#2B2B2B", bg = blue, bold = true })
  hl(0, "PmenuSbar",     { bg = "#3C3F41" })
  hl(0, "PmenuThumb",    { bg = mag })

  -- Line-number gutter: purple accent on the cursor's own line, sign column
  -- transparent.
  hl(0, "CursorLineNr",  { fg = purple, bold = true })
  hl(0, "SignColumn",    { bg = "NONE" })

  -- Messages / prompts.
  hl(0, "Question",      { fg = blue, bold = true })
  hl(0, "MoreMsg",       { fg = blue })
  hl(0, "ModeMsg",       { fg = mag, bold = true })
  hl(0, "Title",         { fg = mag, bold = true })

  -- Merge-conflict regions (git-conflict.nvim). Transparent-ish tints only,
  -- so the conflicting code stays fully readable. ours = blue, theirs = magenta.
  hl(0, "GitConflictCurrent",        { bg = blue_bg })
  hl(0, "GitConflictIncoming",       { bg = mag_bg })
  hl(0, "GitConflictCurrentLabel",   { fg = "#2B2B2B", bg = blue, bold = true })
  hl(0, "GitConflictIncomingLabel",  { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "GitConflictAncestor",       { bg = "#333333" })
  hl(0, "GitConflictAncestorLabel",  { fg = "#2B2B2B", bg = "#888888", bold = true })

  -- Telescope git_status (<leader>gs) diff PREVIEW. Its added/deleted lines are
  -- colored by the built-in `diff` filetype groups (diffAdded/diffRemoved) plus
  -- the treesitter @diff.* groups -- that's why the preview showed solid
  -- green/red instead of the normal code coloring you see elsewhere (new files
  -- avoid this because their preview is shown with the real filetype, not as a
  -- unified diff). Strip the green/red block: keep normal foreground and mark
  -- the change only with a subtle side tint (blue = added, red = removed).
  hl(0, "diffAdded",     { fg = "NONE", bg = blue_bg })
  hl(0, "diffRemoved",   { fg = "NONE", bg = "#4a2530" })
  hl(0, "diffChanged",   { fg = "NONE", bg = blue_bg })
  hl(0, "diffLine",      { fg = mag, bold = true })
  hl(0, "diffFile",      { fg = blue, bold = true })
  hl(0, "diffIndexLine", { fg = "#606366" })
  hl(0, "@diff.plus",    { fg = "NONE", bg = blue_bg })
  hl(0, "@diff.minus",   { fg = "NONE", bg = "#4a2530" })
  hl(0, "@diff.delta",   { fg = "NONE", bg = blue_bg })

  -- Telescope picker chrome: blue selection & prompt, magenta match highlight.
  hl(0, "TelescopeSelection",     { fg = "#A9B7C6", bg = blue_bg, bold = true })
  hl(0, "TelescopeMatching",      { fg = mag, bold = true })
  hl(0, "TelescopePromptPrefix",  { fg = blue })
  hl(0, "TelescopeBorder",        { fg = blue, bg = "NONE" })
  hl(0, "TelescopePromptBorder",  { fg = blue, bg = "NONE" })
  hl(0, "TelescopeResultsBorder", { fg = blue, bg = "NONE" })
  hl(0, "TelescopePreviewBorder", { fg = blue, bg = "NONE" })
  -- The per-window title-text groups (not TelescopeTitle -- that one isn't the
  -- group the borders actually use). Telescope stamps these on the title drawn
  -- into each window's border; left unstyled they resolve to an empty highlight
  -- and the title text renders invisibly against the border, which is why the
  -- "Results" label on the results/prompt divider looked like an empty slot.
  hl(0, "TelescopeResultsTitle",  { fg = mag, bold = true })
  hl(0, "TelescopePromptTitle",   { fg = mag, bold = true })
  hl(0, "TelescopePreviewTitle",  { fg = mag, bold = true })

  -- nvim-tree: files with a git status (what <leader>gs lists) and the folders
  -- containing them, name-tinted only. git-ignored is left out.
  for _, kind in ipairs({ "Dirty", "Staged", "New", "Renamed", "Deleted", "Merge" }) do
    hl(0, "NvimTreeGitFile" .. kind .. "HL",   { fg = purple })
    hl(0, "NvimTreeGitFolder" .. kind .. "HL", { fg = purple })
  end
end
improve_ui_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_ui_colors })
