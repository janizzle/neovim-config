return {
  "akinsho/bufferline.nvim",
  version = "*",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    -- Blue name for buffers with unsaved changes. bufferline exposes no
    -- per-buffer hook for the tab *name* color -- its `groups` feature does,
    -- but groups also cluster the tabs they match, so a buffer would jump to
    -- the front of the strip the moment you typed a character (and <leader>t1-9
    -- would point somewhere else). Patching the single function that resolves
    -- an element's name highlight keeps the order untouched. Colors live in
    -- config/ui.lua as BufferLineChanged*, so they survive a ColorScheme.
    local ok, hl = pcall(require, "bufferline.highlights")
    if ok and type(hl.for_element) == "function" and not hl.__changed_patch then
      local for_element = hl.for_element
      local SELECTED, INACTIVE = 3, 2  -- bufferline.constants.visibility
      hl.for_element = function(element)
        local hls = for_element(element)
        if element and element.modified then
          local v = element:visibility()
          hls.buffer = (v == SELECTED and "BufferLineChangedSelected")
            or (v == INACTIVE and "BufferLineChangedVisible")
            or "BufferLineChanged"
        end
        return hls
      end
      hl.__changed_patch = true
    end

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
