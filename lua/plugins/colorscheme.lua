-- Darcula-dark with a hand-tuned PhpStorm-style palette applied on ColorScheme.

return {
  "xiantang/darcula-dark.nvim",
  lazy = false,
  priority = 1000,
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local function apply_phpstorm_palette()
      local hl = vim.api.nvim_set_hl
      local C = {
        bg          = "#2B2B2B",
        bg_float    = "#3C3F41",
        fg          = "#A9B7C6",
        cursorline  = "#323232",
        line_nr     = "#606366",
        comment     = "#629755",   -- green italic (doc-comment shade)
        string      = "#6A8759",   -- string green (PhpStorm's exact shade)
        number      = "#56B6C2",   -- cyan
        keyword     = "#CC7832",   -- ORANGE bold (unified with types)
        func        = "#61AFEF",   -- BLUE
        named_arg   = "#6897BB",   -- muted darker blue (Darcula's own), kept
                                   -- distinct from func so a `limit:` label
                                   -- never reads as a method name
        variable    = "#C678DD",   -- PURPLE
        type_color  = "#B0B4BA",   -- soft gray (class / type names)
        type_builtin = "#CC7832",  -- ORANGE (scalar type markers: int, bool, string ...)
        tag         = "#E8BF6A",
        attribute   = "#BABABA",
        annotation  = "#BBB529",
        colorcol    = "#555555",   -- thin line-length rule (virt-column)
      }

      hl(0, "Normal",         { fg = C.fg, bg = C.bg })
      -- Floats (LSP hover, diagnostics) use the same background as the buffer
      -- so the K popup doesn't read as a different-colored panel. The blue
      -- FloatBorder still delimits it.
      hl(0, "NormalFloat",    { fg = C.fg, bg = C.bg })
      hl(0, "CursorLine",     { bg = C.cursorline })
      hl(0, "VirtColumn",     { fg = C.colorcol })
      hl(0, "LineNr",         { fg = C.line_nr })
      hl(0, "CursorLineNr",   { fg = C.fg, bold = true })

      hl(0, "Comment",        { fg = C.comment, italic = true })
      hl(0, "String",         { fg = C.string })
      hl(0, "Character",      { fg = C.string })
      hl(0, "Number",         { fg = C.number })
      hl(0, "Float",          { fg = C.number })
      hl(0, "Boolean",        { fg = C.keyword, bold = true })
      hl(0, "Keyword",        { fg = C.keyword, bold = true })
      hl(0, "Statement",      { fg = C.keyword, bold = true })
      hl(0, "Conditional",    { fg = C.keyword, bold = true })
      hl(0, "Repeat",         { fg = C.keyword, bold = true })
      hl(0, "Operator",       { fg = C.fg })
      hl(0, "Function",       { fg = C.func })
      hl(0, "Identifier",     { fg = C.variable })
      hl(0, "Type",           { fg = C.type_color, bold = true })
      hl(0, "StorageClass",   { fg = C.keyword, bold = true })
      hl(0, "Structure",      { fg = C.type_color, bold = true })
      hl(0, "Constant",       { fg = C.variable })
      hl(0, "Special",        { fg = C.keyword })
      hl(0, "PreProc",        { fg = C.annotation })
      hl(0, "Define",         { fg = C.keyword, bold = true })

      hl(0, "@keyword",              { fg = C.keyword, bold = true })
      hl(0, "@keyword.function",     { fg = C.keyword, bold = true })
      hl(0, "@keyword.return",       { fg = C.keyword, bold = true })
      hl(0, "@keyword.operator",     { fg = C.keyword, bold = true })
      hl(0, "@keyword.import",       { fg = C.keyword, bold = true })
      hl(0, "@keyword.modifier",     { fg = C.keyword, bold = true })
      hl(0, "@string",               { fg = C.string })
      hl(0, "@string.escape",        { fg = C.keyword, bold = true })
      hl(0, "@number",               { fg = C.number })
      hl(0, "@boolean",              { fg = C.keyword, bold = true })
      hl(0, "@comment",              { fg = C.comment, italic = true })
      hl(0, "@function",             { fg = C.func })
      hl(0, "@function.call",        { fg = C.func })
      hl(0, "@function.builtin",     { fg = C.func })
      hl(0, "@method",               { fg = C.func })
      hl(0, "@method.call",          { fg = C.func })
      hl(0, "@constructor",          { fg = C.type_color, bold = true })
      hl(0, "@variable",             { fg = C.variable })
      hl(0, "@variable.member",      { fg = C.variable })
      hl(0, "@variable.builtin",     { fg = C.keyword, italic = true })
      hl(0, "@property",             { fg = C.variable })
      hl(0, "@parameter",            { fg = C.variable })
      -- The label of a NAMED argument -- the `limit:` in `f(limit: 10)`. Blue,
      -- as in PhpStorm, but a darker blue than methods so the two don't blur
      -- together at a glance. It gets its own capture (see
      -- after/queries/php_only/highlights.scm) precisely so this stays surgical:
      -- the upstream query lumps it in with @variable.parameter, which also
      -- covers the `$x` in a function signature, and those stay purple.
      hl(0, "@variable.parameter.named", { fg = C.named_arg })
      hl(0, "@constant",             { fg = C.variable, bold = true })
      hl(0, "@constant.builtin",     { fg = C.keyword, italic = true })
      hl(0, "@type",                 { fg = C.type_color, bold = true })
      hl(0, "@type.builtin",         { fg = C.type_builtin, bold = true })
      hl(0, "@type.definition",      { fg = C.type_color, bold = true })
      hl(0, "@tag",                  { fg = C.tag })
      hl(0, "@tag.attribute",        { fg = C.attribute })
      hl(0, "@tag.delimiter",        { fg = C.fg })
      hl(0, "@attribute",            { fg = C.annotation })
      hl(0, "@operator",             { fg = C.fg })
      hl(0, "@punctuation",          { fg = C.fg })
      hl(0, "@punctuation.bracket",  { fg = C.fg })
      hl(0, "@punctuation.delimiter",{ fg = C.fg })
      hl(0, "@punctuation.special",  { fg = C.variable })

      hl(0, "phpVarSelector",  { fg = C.variable })
      hl(0, "phpIdentifier",   { fg = C.variable })
      hl(0, "phpMethodsVar",   { fg = C.variable })
      hl(0, "phpFunctions",    { fg = C.func })
      hl(0, "phpMethod",       { fg = C.func })
      hl(0, "phpClasses",      { fg = C.type_color, bold = true })
      hl(0, "phpStructure",    { fg = C.type_color, bold = true })
      hl(0, "phpStatement",    { fg = C.keyword, bold = true })
      hl(0, "phpKeyword",      { fg = C.keyword, bold = true })
      hl(0, "phpType",         { fg = C.type_builtin, bold = true })
      hl(0, "phpStorageClass", { fg = C.keyword, bold = true })
      hl(0, "phpDefine",       { fg = C.keyword, bold = true })
      hl(0, "phpInclude",      { fg = C.keyword, bold = true })
      hl(0, "phpRegion",       { fg = C.fg })

      hl(0, "htmlTag",         { fg = C.fg })
      hl(0, "htmlEndTag",      { fg = C.fg })
      hl(0, "htmlTagName",     { fg = C.tag })
      hl(0, "htmlArg",         { fg = C.attribute })
      hl(0, "htmlString",      { fg = C.string })
      hl(0, "htmlSpecialChar", { fg = C.keyword })

      hl(0, "javaScriptFunction",    { fg = C.keyword, bold = true })
      hl(0, "javaScriptIdentifier",  { fg = C.keyword, bold = true })
      hl(0, "javaScriptType",        { fg = C.type_color, bold = true })
      hl(0, "javaScriptNumber",      { fg = C.number })
      hl(0, "javaScriptBoolean",     { fg = C.keyword, bold = true })
      hl(0, "javaScriptNull",        { fg = C.keyword, bold = true })

      hl(0, "@lsp.type.namespace",   { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.class",       { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.interface",   { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.struct",      { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.enum",        { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.type",        { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.typeParameter", { fg = C.type_color, bold = true })
      hl(0, "@lsp.type.method",      { fg = C.func })
      hl(0, "@lsp.type.function",    { fg = C.func })
      hl(0, "@lsp.type.parameter",   { fg = C.variable })
      hl(0, "@lsp.type.property",    { fg = C.variable })
      hl(0, "@lsp.type.variable",    { fg = C.variable })
      hl(0, "@lsp.type.enumMember",  { fg = C.variable, bold = true })

      -- Twig ({{ }} / {% %}) -- vim-twig regex groups mapped to the palette.
      hl(0, "twigVarDelim",     { fg = C.keyword, bold = true })   -- {{  }}
      hl(0, "twigTagDelim",     { fg = C.keyword, bold = true })   -- {%  %}
      hl(0, "twigVarBlock",     { fg = C.fg })                     -- default inside {{ }}
      hl(0, "twigTagBlock",     { fg = C.fg })                     -- default inside {% %}
      hl(0, "twigStatement",    { fg = C.keyword, bold = true })   -- if / for / block / set ...
      hl(0, "twigSpecial",      { fg = C.keyword, italic = true }) -- true / false / none / loop
      hl(0, "twigOperator",     { fg = C.fg })                     -- | . + - == ...
      hl(0, "twigFilter",       { fg = C.func })                   -- |upper, |date ...
      hl(0, "twigFunction",     { fg = C.func })                   -- path(), asset() ...
      hl(0, "twigBlockName",    { fg = C.func })
      hl(0, "twigVariable",     { fg = C.variable })
      hl(0, "twigAttribute",    { fg = C.variable })               -- .name in user.name
      hl(0, "twigString",       { fg = C.string })
      hl(0, "twigNumber",       { fg = C.number })
      hl(0, "twigComment",      { fg = C.comment, italic = true }) -- {# ... #}
      hl(0, "twigCommentDelim", { fg = C.comment, italic = true })
      hl(0, "twigRawDelim",     { fg = C.keyword, bold = true })
    end

    vim.api.nvim_create_autocmd("ColorScheme", { callback = apply_phpstorm_palette })
    vim.cmd.colorscheme("darcula-dark")
  end,
}
