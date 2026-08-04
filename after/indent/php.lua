-- Sourced after $VIMRUNTIME/indent/php.vim, which sets 'noautoindent'.
-- The treesitter indentexpr returns -1 for lines it can't work out (broken
-- tree while typing incomplete code), and -1 falls back to autoindent --
-- switched off, that means column 0. Keep autoindent on so "can't tell"
-- keeps the current indent instead.
vim.bo.autoindent = true
