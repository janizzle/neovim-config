-- UI chrome recoloring not tied to a single plugin: diff backgrounds and the
-- blue+magenta accent scheme. Reapplied on ColorScheme to survive reloads.

local C = require("config.palette")

-- Less washed-out diff colors (darcula's DiffChange is a muddy grey and
-- DiffDelete has no background). Tuned for the near-black background: dark
-- enough not to glow, saturated enough to read as green/blue/red tints.
local function improve_diff_colors()
  vim.api.nvim_set_hl(0, "DiffAdd",    { bg = C.diff_add, fg = "NONE" })     -- added / OURS side
  vim.api.nvim_set_hl(0, "DiffChange", { bg = C.diff_change, fg = "NONE" })  -- changed line (context)
  vim.api.nvim_set_hl(0, "DiffText",   { bg = C.diff_text, fg = "NONE", bold = true })  -- exact changed chars
  vim.api.nvim_set_hl(0, "DiffDelete", { bg = C.diff_delete, fg = "#6A2F3C" })  -- removed / THEIRS side
end
improve_diff_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_diff_colors })

-- Blue + magenta accents on interface elements only (borders, selections,
-- search, menus, conflict regions); window backgrounds, icon colors and code
-- syntax are deliberately untouched, backgrounds stay transparent or a faint
-- tint so code underneath remains readable.
local function improve_ui_colors()
  local hl   = vim.api.nvim_set_hl
  local blue = C.blue
  local mag  = C.magenta
  local purple = C.purple      -- same purple the palette uses for variables
  local blue_bg = C.bg_blue    -- faint tints
  local mag_bg  = C.bg_mag

  -- Selection / search / cursor accents.
  hl(0, "Visual",        { bg = blue_bg })
  hl(0, "VisualNOS",     { bg = blue_bg })
  hl(0, "Search",        { fg = "NONE", bg = mag_bg })
  hl(0, "IncSearch",     { fg = C.bg, bg = mag, bold = true })
  hl(0, "CurSearch",     { fg = C.bg, bg = mag, bold = true })
  hl(0, "MatchParen",    { fg = mag, bold = true, bg = "NONE" })

  -- Floating-window borders (VertSplit left at the theme default).
  hl(0, "FloatBorder",   { fg = blue, bg = "NONE" })
  hl(0, "FloatTitle",    { fg = mag, bold = true, bg = "NONE" })

  -- Popup / completion menu.
  hl(0, "Pmenu",         { fg = C.fg, bg = C.bg_alt })
  hl(0, "PmenuSel",      { fg = C.bg, bg = blue, bold = true })
  hl(0, "PmenuSbar",     { bg = C.bg_alt })
  hl(0, "PmenuThumb",    { bg = mag })

  -- Gutter.
  hl(0, "CursorLineNr",  { fg = purple, bold = true })
  hl(0, "SignColumn",    { bg = "NONE" })

  -- Messages / prompts.
  hl(0, "Question",      { fg = blue, bold = true })
  hl(0, "MoreMsg",       { fg = blue })
  hl(0, "ModeMsg",       { fg = mag, bold = true })
  hl(0, "Title",         { fg = mag, bold = true })

  -- Merge conflicts. One colour language everywhere -- blue = OURS, green =
  -- THEIRS -- so the same block reads the same in the side panes, in the middle
  -- pane and when editing the file inline. The marker lines are solid bars:
  -- they are the structure you scan by, so they get the strong colour and the
  -- regions themselves only a tint.
  hl(0, "GitConflictCurrent",        { bg = C.merge_ours })
  hl(0, "GitConflictIncoming",       { bg = C.merge_theirs })
  hl(0, "GitConflictCurrentLabel",   { fg = C.bg, bg = blue, bold = true })
  hl(0, "GitConflictIncomingLabel",  { fg = C.bg, bg = purple, bold = true })
  hl(0, "GitConflictAncestor",       { bg = C.bg_alt })
  hl(0, "GitConflictAncestorLabel",  { fg = C.bg, bg = "#888888", bold = true })

  -- Merge-tool panes, applied per window by config/merge.lua. Every differing
  -- line in the OURS pane is blue and every differing line in the THEIRS pane is
  -- purple, so a pane's colour *is* its identity -- there is no neutral "these
  -- lines differ" any more. Missing lines stay quiet rather than a block of red,
  -- because red is reserved for conflicts.
  hl(0, "MergeOursDiff",       { bg = C.merge_ours })
  hl(0, "MergeOursDiffText",   { bg = C.merge_ours_text, bold = true })
  hl(0, "MergeTheirsDiff",     { bg = C.merge_theirs })
  hl(0, "MergeTheirsDiffText", { bg = C.merge_theirs_text, bold = true })
  -- The result pane never shows vim's own diff highlighting -- only open
  -- conflicts are coloured there (see below) -- so it is mapped to this; side
  -- panes switch to it too once they paint themselves.
  hl(0, "MergeResultPlain",    { bg = "NONE" })
  hl(0, "MergeFiller",         { fg = C.merge_filler_fg, bg = C.merge_filler_bg })
  -- diffview links this to Comment by default, which paints every absent-line
  -- region in comment green -- exactly the colour that reads as "added".
  hl(0, "DiffviewDiffDeleteDim", { fg = C.merge_filler_fg, bg = C.merge_filler_bg, italic = false })

  -- Result pane (config/mergeresult.lua), painted by us rather than by the diff
  -- engine: red marks an open conflict, still waiting on ct/co/cb/c0, and
  -- nothing else is coloured -- auto-merged lines and answered conflicts stay
  -- plain, so red is only ever what is still left to do.
  hl(0, "MergeConflict",      { bg = C.merge_conflict })
  hl(0, "MergeConflictTag",   { fg = C.red, bold = true })
  hl(0, "MergeHintTag",       { fg = C.line_nr, italic = true })
  -- Side panes (paint_side): what that side changed against the merge base.
  hl(0, "MergeAutoOurs",      { bg = C.merge_ours })
  hl(0, "MergeAutoTheirs",    { bg = C.merge_theirs })
  -- Gutter bracket: the only mark that means "co/ct/cb/c0 work here". The
  -- corner pieces close each block off, so two conflicts that touch never read
  -- as one.
  hl(0, "MergeSignConflict",  { fg = C.red, bg = C.merge_conflict, bold = true })

  -- Side-by-side file diff (config/sidediff.lua): the pane you edit is blue,
  -- the committed one is quiet chrome -- you should never have to look twice to
  -- see which half is yours.
  hl(0, "DiffSideWinbarNew",  { fg = C.bg, bg = blue, bold = true })
  hl(0, "DiffSideWinbarOld",  { fg = C.fg, bg = C.bg_alt, bold = true })
  hl(0, "DiffSideWinbarFill", { fg = C.line_nr, bg = C.bg })

  -- Pane headers (winbar) -- which side am I looking at.
  hl(0, "MergeWinbarOurs",   { fg = C.bg, bg = blue, bold = true })
  hl(0, "MergeWinbarTheirs", { fg = C.bg, bg = purple, bold = true })
  hl(0, "MergeWinbarResult", { fg = C.bg, bg = C.fg, bold = true })
  hl(0, "MergeWinbarSide",   { fg = C.fg, bg = C.bg_alt, bold = true })
  hl(0, "MergeWinbarFill",   { fg = C.line_nr, bg = C.bg })

  -- diffview's own file panel, below our conflict list. Unstyled it inherits
  -- darcula's Directory for its section titles and folder rows, which is the
  -- one yellow left in the whole view; the panel is chrome, so it belongs in
  -- the same blue as the rest of the chrome.
  hl(0, "DiffviewFilePanelTitle",     { fg = blue, bold = true })
  hl(0, "DiffviewFilePanelRootPath",  { fg = blue, bold = true })
  hl(0, "DiffviewFilePanelCounter",   { fg = C.line_nr, bold = true })
  hl(0, "DiffviewFilePanelFileName",  { fg = C.fg })
  hl(0, "DiffviewFilePanelPath",      { fg = C.line_nr })
  hl(0, "DiffviewFolderName",         { fg = blue })
  hl(0, "DiffviewFolderSign",         { fg = C.line_nr })
  hl(0, "DiffviewFilePanelInsertions", { fg = C.green })
  hl(0, "DiffviewFilePanelDeletions",  { fg = C.red })
  hl(0, "DiffviewFilePanelConflicts",  { fg = C.red, bold = true })
  -- Per-file git status letters, in the same colour language: blue is a change
  -- of ours, purple something that arrived, red something gone or unmerged.
  hl(0, "DiffviewStatusModified",    { fg = blue })
  hl(0, "DiffviewStatusRenamed",     { fg = purple })
  hl(0, "DiffviewStatusCopied",      { fg = purple })
  hl(0, "DiffviewStatusUntracked",   { fg = purple })
  hl(0, "DiffviewStatusAdded",       { fg = C.green })
  hl(0, "DiffviewStatusDeleted",     { fg = C.red })
  hl(0, "DiffviewStatusUnmerged",    { fg = C.red, bold = true })
  hl(0, "DiffviewStatusTypeChanged", { fg = C.fg })
  hl(0, "DiffviewStatusIgnored",     { fg = C.line_nr })
  hl(0, "DiffviewStatusUnknown",     { fg = C.line_nr })
  hl(0, "DiffviewReference",         { fg = blue, bold = true })
  hl(0, "DiffviewHash",              { fg = C.line_nr })

  -- Conflict list stacked above diffview's file panel (config/merge.lua).
  hl(0, "MergeConflictsNormal",     { fg = C.fg, bg = C.bg })
  hl(0, "MergeConflictsCursorLine", { bg = blue_bg })
  hl(0, "MergeConflictsTitle",      { fg = mag, bold = true })
  hl(0, "MergeConflictsCount",      { fg = C.red, bold = true })
  hl(0, "MergeConflictsDone",       { fg = C.green, bold = true })
  hl(0, "MergeConflictsPath",       { fg = C.fg })
  hl(0, "MergeConflictsDir",        { fg = C.line_nr })
  hl(0, "MergeConflictsEmpty",      { fg = C.line_nr, italic = true })

  -- Unified-diff previews (<leader>gs on files whose preview is a diff): the
  -- diff/@diff groups would paint solid green/red blocks over the code; keep
  -- normal foreground and mark changes with a subtle background tint instead.
  hl(0, "diffAdded",     { fg = "NONE", bg = blue_bg })
  hl(0, "diffRemoved",   { fg = "NONE", bg = C.diff_delete })
  hl(0, "diffChanged",   { fg = "NONE", bg = blue_bg })
  hl(0, "diffLine",      { fg = mag, bold = true })
  hl(0, "diffFile",      { fg = blue, bold = true })
  hl(0, "diffIndexLine", { fg = C.line_nr })
  hl(0, "@diff.plus",    { fg = "NONE", bg = blue_bg })
  hl(0, "@diff.minus",   { fg = "NONE", bg = C.diff_delete })
  hl(0, "@diff.delta",   { fg = "NONE", bg = blue_bg })

  -- Telescope chrome: blue selection & borders, magenta match highlight.
  hl(0, "TelescopeNormal",        { fg = C.fg, bg = C.bg })
  hl(0, "TelescopeSelection",     { fg = C.fg, bg = blue_bg, bold = true })
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

  -- nvim-tree surfaces: same near-black as the editor so the sidebar doesn't
  -- sit on the theme's lighter grey.
  hl(0, "NvimTreeNormal",    { fg = C.fg, bg = C.bg })
  hl(0, "NvimTreeNormalNC",  { fg = C.fg, bg = C.bg })
  hl(0, "NvimTreeWinSeparator", { fg = C.bg_alt, bg = C.bg })
  hl(0, "NvimTreeEndOfBuffer",  { fg = C.bg, bg = C.bg })

  -- Buffer tabs. Names are neutral grey (darcula's TabLineSel is olive green,
  -- which bufferline inherits for every tab); buffers with unsaved changes get
  -- a blue name via the "changed" group declared in plugins/bufferline.lua,
  -- plus a blue modified dot. Devicons keep their own colors.
  local tab_dim  = "#6E767E"   -- listed but not on screen
  local tab_open = "#98A2AC"   -- open in another window
  hl(0, "BufferLineFill",              { bg = C.bg })
  hl(0, "BufferLineBackground",        { fg = tab_dim,  bg = C.bg })
  hl(0, "BufferLineBufferVisible",     { fg = tab_open, bg = C.bg })
  hl(0, "BufferLineBufferSelected",    { fg = C.fg,     bg = C.bg_sel, bold = true, italic = false })
  hl(0, "BufferLineChanged",           { fg = blue,     bg = C.bg })
  hl(0, "BufferLineChangedVisible",    { fg = blue,     bg = C.bg })
  hl(0, "BufferLineChangedSelected",   { fg = blue,     bg = C.bg_sel, bold = true, italic = false })
  hl(0, "BufferLineModified",          { fg = blue,     bg = C.bg })
  hl(0, "BufferLineModifiedVisible",   { fg = blue,     bg = C.bg })
  hl(0, "BufferLineModifiedSelected",  { fg = blue,     bg = C.bg_sel })
  hl(0, "BufferLineIndicatorSelected", { fg = blue,     bg = C.bg_sel })
  hl(0, "BufferLineSeparator",         { fg = C.bg_alt, bg = C.bg })
  hl(0, "BufferLineSeparatorVisible",  { fg = C.bg_alt, bg = C.bg })
  hl(0, "BufferLineSeparatorSelected", { fg = C.bg_alt, bg = C.bg_sel })
  hl(0, "BufferLineCloseButton",       { fg = tab_dim,  bg = C.bg })
  hl(0, "BufferLineCloseButtonVisible", { fg = tab_open, bg = C.bg })
  hl(0, "BufferLineCloseButtonSelected", { fg = C.fg,   bg = C.bg_sel })
  hl(0, "BufferLineOffsetSeparator",   { fg = C.bg_alt, bg = C.bg })
  hl(0, "BufferLineTabSeparator",      { fg = C.bg_alt, bg = C.bg })
  hl(0, "BufferLineTruncMarker",       { fg = tab_dim,  bg = C.bg })

  -- nvim-tree: files with a git status (and their folders), name-tinted only.
  for _, kind in ipairs({ "Dirty", "Staged", "New", "Renamed", "Deleted", "Merge" }) do
    hl(0, "NvimTreeGitFile" .. kind .. "HL",   { fg = purple })
    hl(0, "NvimTreeGitFolder" .. kind .. "HL", { fg = purple })
  end
end
improve_ui_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = improve_ui_colors })
