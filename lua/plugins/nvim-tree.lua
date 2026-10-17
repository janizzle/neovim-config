return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    require("nvim-tree").setup({
      hijack_netrw = true,
      view = {
        width = 50,
        side = "left",
        preserve_window_proportions = true,
        signcolumn = "no",
        number = true,
        relativenumber = true,
      },
      renderer = {
        -- Changed files marked ONLY by tinting the name purple ("name", with
        -- git icons off): no ✗/★/✓ markers, the color is the whole marker.
        highlight_git = "name",
        icons = {
          show = { folder = true, file = true, git = false, folder_arrow = true },
        },
      },
      update_focused_file = { enable = true, update_root = false },
      -- git_ignored=false keeps ignored files listed.
      filters = { dotfiles = false, git_ignored = false },
      -- Required for highlight_git; without it nodes carry no status.
      git = { enable = true },
      actions = {
        open_file = {
          -- With more than one view, opening a file asks which one (letter
          -- overlay). nvim-tree's default exclude list plus the blame column,
          -- so a file can never land in it.
          window_picker = {
            exclude = {
              filetype = { "notify", "packer", "qf", "diff", "fugitive", "fugitiveblame", "blame" },
              buftype = { "nofile", "terminal", "help" },
            },
          },
        },
      },
    })
  end,
}
