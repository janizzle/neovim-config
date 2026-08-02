;; extends

; Named arguments: the LABEL in `f(limit: 10)`.
;
; PhpStorm paints that label blue; nvim-treesitter's own rule paints it with
; the same purple as every other variable, because it captures it as
; @variable.parameter -- the group it also uses for the `$x` in a function
; SIGNATURE. Re-colouring @variable.parameter would therefore drag the
; signature parameters along with it, so the label gets a group of its own
; (@variable.parameter.named, coloured in plugins/colorscheme.lua) and nothing
; else moves.
;
; The `name:` field is load-bearing. Upstream matches `(argument (name))` with
; no field, which ALSO matches a bare constant passed positionally --
; `f(SOME_CONST)` -- so dropping the field would recolour constants too.
; Priority 200 puts this above the base query's capture on the same node.
(argument
  name: (name) @variable.parameter.named
  (#set! priority 200))
