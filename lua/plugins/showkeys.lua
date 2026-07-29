-- On-screen keystroke display (top-right), toggled on at startup.

return {
  "nvzone/showkeys",
  lazy = false,
  opts = {
    timeout = 999999,
    maxkeys = 5,
    position = "top-right",
    show_count = true,
  },
  config = function(_, opts)
    require("showkeys").setup(opts)
    vim.cmd("ShowkeysToggle")
  end,
}
