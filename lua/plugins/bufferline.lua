return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    require("bufferline").setup({
      options = {
        diagnostics = "nvim_lsp",
        offsets = {
          { filetype = "NvimTree", text = "Project", separator = true, text_align = "left" },
        },
        -- Label the start screen's scratch buffer "Welcome" instead of
        -- "[No Name]" (tagged by welcome.paint()).
        name_formatter = function(buf)
          if vim.b[buf.bufnr] and vim.b[buf.bufnr].welcome_screen then return "Welcome" end
        end,
        show_buffer_close_icons = true,
        show_close_icon = false,
        separator_style = "thin",
        custom_filter = function(buf)
          return vim.bo[buf].buftype ~= "terminal"
        end,
      },
    })
  end,
}
