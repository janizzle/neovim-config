return {
  "nvim-tree/nvim-web-devicons",
  config = function()
    require("nvim-web-devicons").setup({
      -- Force real glyphs; only meaningful when the terminal font is a
      -- Nerd Font. Turns off the color-only ASCII fallback.
      color_icons = true,
      default = true,
    })
  end,
}
