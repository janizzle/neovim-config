-- On-screen keystroke display (bottom-right, small and gray), toggled on at startup.

return {
  "nvzone/showkeys",
  lazy = false,
  opts = {
    timeout = 999999,
    maxkeys = 3,
    position = "bottom-right",
    show_count = false,
  },
  config = function(_, opts)
    require("showkeys").setup(opts)
    -- Muted: no filled background, gray text.
    vim.api.nvim_set_hl(0, "SkInactive", { fg = "#5c6370", bg = "NONE" })
    vim.api.nvim_set_hl(0, "SkActive", { fg = "#7f848e", bg = "NONE" })
    vim.cmd("ShowkeysToggle")
  end,
}
