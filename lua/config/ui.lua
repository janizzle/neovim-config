-- UI chrome recoloring not tied to a single plugin: diff backgrounds and the
-- blue+magenta accent scheme. Reapplied on ColorScheme to survive reloads.

-- Less washed-out diff colors (darcula's DiffChange is a muddy grey and
-- DiffDelete has no background).
local function improve_diff_colors()
  vim.api.nvim_set_hl(0, "DiffAdd",    { bg = "#20402a", fg = "NONE" })  -- added / OURS side
  vim.api.nvim_set_hl(0, "DiffChange", { bg = "#25314a", fg = "NONE" })  -- changed line (context)
  vim.api.nvim_set_hl(0, "DiffText",   { bg = "#3a5279", fg = "NONE", bold = true })  -- exact changed chars
  vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#4a2530", fg = "#7a3b48" })  -- removed / THEIRS side
end
improve_diff_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_diff_colors })

-- Blue + magenta accents on interface elements only (borders, selections,
-- search, menus, conflict regions); window backgrounds, icon colors and code
-- syntax are deliberately untouched, backgrounds stay transparent or a faint
-- tint so code underneath remains readable.
local function improve_ui_colors()
  local hl   = vim.api.nvim_set_hl
  local blue = "#61AFEF"
  local mag  = "#c264c9"
  local purple = "#C678DD"     -- same purple the palette uses for variables
  local blue_bg = "#22384f"    -- faint tints
  local mag_bg  = "#3a2740"

  -- Selection / search / cursor accents.
  hl(0, "Visual",        { bg = blue_bg })
  hl(0, "VisualNOS",     { bg = blue_bg })
  hl(0, "Search",        { fg = "NONE", bg = mag_bg })
  hl(0, "IncSearch",     { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "CurSearch",     { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "MatchParen",    { fg = mag, bold = true, bg = "NONE" })

  -- Floating-window borders (VertSplit left at the theme default).
  hl(0, "FloatBorder",   { fg = blue, bg = "NONE" })
  hl(0, "FloatTitle",    { fg = mag, bold = true, bg = "NONE" })

  -- Popup / completion menu.
  hl(0, "Pmenu",         { fg = "#A9B7C6", bg = "#3C3F41" })
  hl(0, "PmenuSel",      { fg = "#2B2B2B", bg = blue, bold = true })
  hl(0, "PmenuSbar",     { bg = "#3C3F41" })
  hl(0, "PmenuThumb",    { bg = mag })

  -- Gutter.
  hl(0, "CursorLineNr",  { fg = purple, bold = true })
  hl(0, "SignColumn",    { bg = "NONE" })

  -- Messages / prompts.
  hl(0, "Question",      { fg = blue, bold = true })
  hl(0, "MoreMsg",       { fg = blue })
  hl(0, "ModeMsg",       { fg = mag, bold = true })
  hl(0, "Title",         { fg = mag, bold = true })

  -- Merge-conflict regions (git-conflict.nvim): ours = blue, theirs = magenta.
  hl(0, "GitConflictCurrent",        { bg = blue_bg })
  hl(0, "GitConflictIncoming",       { bg = mag_bg })
  hl(0, "GitConflictCurrentLabel",   { fg = "#2B2B2B", bg = blue, bold = true })
  hl(0, "GitConflictIncomingLabel",  { fg = "#2B2B2B", bg = mag, bold = true })
  hl(0, "GitConflictAncestor",       { bg = "#333333" })
  hl(0, "GitConflictAncestorLabel",  { fg = "#2B2B2B", bg = "#888888", bold = true })

  -- Unified-diff previews (<leader>gs on files whose preview is a diff): the
  -- diff/@diff groups would paint solid green/red blocks over the code; keep
  -- normal foreground and mark changes with a subtle background tint instead.
  hl(0, "diffAdded",     { fg = "NONE", bg = blue_bg })
  hl(0, "diffRemoved",   { fg = "NONE", bg = "#4a2530" })
  hl(0, "diffChanged",   { fg = "NONE", bg = blue_bg })
  hl(0, "diffLine",      { fg = mag, bold = true })
  hl(0, "diffFile",      { fg = blue, bold = true })
  hl(0, "diffIndexLine", { fg = "#606366" })
  hl(0, "@diff.plus",    { fg = "NONE", bg = blue_bg })
  hl(0, "@diff.minus",   { fg = "NONE", bg = "#4a2530" })
  hl(0, "@diff.delta",   { fg = "NONE", bg = blue_bg })

  -- Telescope chrome: blue selection & borders, magenta match highlight.
  hl(0, "TelescopeSelection",     { fg = "#A9B7C6", bg = blue_bg, bold = true })
  hl(0, "TelescopeMatching",      { fg = mag, bold = true })
  hl(0, "TelescopePromptPrefix",  { fg = blue })
  hl(0, "TelescopeBorder",        { fg = blue, bg = "NONE" })
  hl(0, "TelescopePromptBorder",  { fg = blue, bg = "NONE" })
  hl(0, "TelescopeResultsBorder", { fg = blue, bg = "NONE" })
  hl(0, "TelescopePreviewBorder", { fg = blue, bg = "NONE" })
  -- The border-title groups (not TelescopeTitle); unstyled they resolve empty
  -- and the "Results"/"Prompt" labels render invisibly.
  hl(0, "TelescopeResultsTitle",  { fg = mag, bold = true })
  hl(0, "TelescopePromptTitle",   { fg = mag, bold = true })
  hl(0, "TelescopePreviewTitle",  { fg = mag, bold = true })

  -- nvim-tree: files with a git status (and their folders), name-tinted only.
  for _, kind in ipairs({ "Dirty", "Staged", "New", "Renamed", "Deleted", "Merge" }) do
    hl(0, "NvimTreeGitFile" .. kind .. "HL",   { fg = purple })
    hl(0, "NvimTreeGitFolder" .. kind .. "HL", { fg = purple })
  end
end
improve_ui_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_ui_colors })
