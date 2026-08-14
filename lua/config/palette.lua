-- Single source of truth for the hand-tuned PhpStorm-style palette.
-- Required by plugins/colorscheme.lua (syntax) and config/ui.lua (chrome), so
-- the near-black background is defined in exactly one place.

return {
  -- Surfaces ------------------------------------------------------------------
  bg          = "#0B0B0D",   -- editor background: almost black
  bg_alt      = "#141418",   -- popups / panels that need to lift off the page
  bg_sel      = "#17171C",   -- cursorline and other faint row tints
  bg_blue     = "#16283A",   -- faint blue tint (selection, OURS regions)
  bg_mag      = "#2C1B32",   -- faint magenta tint (search, THEIRS regions)

  -- Text ----------------------------------------------------------------------
  fg          = "#A9B7C6",
  line_nr     = "#4E5157",
  whitespace  = "#2A2A31",   -- listchars dots / eol arrows: present but quiet
  colorcol    = "#2E2E35",   -- thin line-length rule (virt-column)

  -- Accents -------------------------------------------------------------------
  blue        = "#61AFEF",
  magenta     = "#C264C9",
  purple      = "#C678DD",
  green       = "#98C379",
  red         = "#E06C75",

  -- Syntax --------------------------------------------------------------------
  comment      = "#629755",  -- green italic
  string       = "#6A8759",
  number       = "#56B6C2",  -- cyan
  keyword      = "#CC7832",  -- orange bold
  func         = "#61AFEF",  -- blue
  named_arg    = "#6897BB",  -- darker blue, distinct from func
  variable     = "#C678DD",  -- purple
  type_color   = "#B0B4BA",  -- soft gray (class / type names)
  type_builtin = "#CC7832",  -- orange (int, bool, string, ...)
  tag          = "#E8BF6A",
  attribute    = "#BABABA",
  annotation   = "#BBB529",

  -- Diff surfaces -- dark enough for near-black, bright enough to read as tints.
  diff_add    = "#12301D",
  diff_change = "#152340",
  diff_text   = "#274268",
  diff_delete = "#33161F",

  -- Merge tool. One colour language across all three panes, IntelliJ-style:
  -- blue is always OURS, purple is always THEIRS, red is always "this is a
  -- conflict and it is waiting on a decision". Denser than the plain diff
  -- surfaces above: the merge tool is a place you read by colour, so the tints
  -- have to carry across three panes at a glance.
  merge_ours          = "#152D45",   -- a line that came from our side
  merge_ours_text     = "#24527E",   -- the characters that actually differ
  merge_theirs        = "#2B1743",   -- a line that came from their side
  merge_theirs_text   = "#4A2D75",
  -- Conflicts: solid warm red, never a tint you could confuse with the two
  -- sides. The band is one block; `_text` is the same red, a shade up, for the
  -- differing characters inside it.
  merge_conflict      = "#411620",
  merge_conflict_text = "#5C1D29",
  merge_local         = "#1C1F26",   -- your own edits: matches neither side
  merge_filler_bg     = "#0E0E12",
  merge_filler_fg     = "#26262C",
  merge_center        = "#191922",   -- result pane before it is taken over
  merge_center_text   = "#262631",
}
