return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    -- Close the git-blame column before the tree opens any file. Without this,
    -- NvimTree (window_picker disabled) can pick the narrow blame window as the
    -- open target, so the file loads INTO the blame column. Wrapping the tree's
    -- default Enter/open actions guarantees blame is gone first.
    local function on_attach(bufnr)
      local api = require("nvim-tree.api")
      api.config.mappings.default_on_attach(bufnr)
      local function opts(desc)
        return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
      end
      local function open_after_blame_close()
        pcall(function() require("config.blame").close() end)
        api.node.open.edit()
      end
      vim.keymap.set("n", "<CR>", open_after_blame_close, opts("Open"))
      vim.keymap.set("n", "o", open_after_blame_close, opts("Open"))
      vim.keymap.set("n", "<2-LeftMouse>", open_after_blame_close, opts("Open"))
    end

    require("nvim-tree").setup({
      on_attach = on_attach,
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
        -- Changed files (the same set <leader>gs lists) are marked ONLY by
        -- tinting the file name in the accent purple -- "name", never "icon"
        -- or "all". With icons.show.git left off, the old status markers
        -- (✗ ★ ✓ ➜ ...) and their per-status colors stay gone: the tree keeps
        -- its plain structure and the color is the whole marker.
        highlight_git = "name",
        icons = {
          show = { folder = true, file = true, git = false, folder_arrow = true },
        },
      },
      update_focused_file = { enable = true, update_root = false },
      -- git_ignored = false keeps ignored files listed as before -- enabling the
      -- git integration would otherwise start hiding them.
      filters = { dotfiles = false, git_ignored = false },
      -- Required for highlight_git: without it nodes carry no status at all.
      git = { enable = true },
      actions = {
        open_file = {
          window_picker = { enable = false },
        },
      },
    })
  end,
}
