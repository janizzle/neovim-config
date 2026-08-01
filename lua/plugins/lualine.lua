return {
  "nvim-lualine/lualine.nvim",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    -- Total lines in the buffer, so the right end of the statusline reads
    -- "42%  340 lines  12:5" -- where the cursor is, and how much there is.
    -- Only used in `sections` (the ACTIVE window): a lualine component has no
    -- handle on the window it is being drawn for, so in `inactive_sections`
    -- this would report the current buffer's count for every other split.
    local function total_lines()
      return vim.api.nvim_buf_line_count(0) .. " lines"
    end

    require("lualine").setup({
      options = { theme = "auto", section_separators = "", component_separators = "" },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        -- `fmt` post-processes the rendered string, so the modified/readonly
        -- flags keep working -- it only relabels the start screen's scratch
        -- buffer, which would otherwise show as "[No Name]".
        lualine_c = {
          { "filename", fmt = function(str) return vim.b.welcome_screen and "Welcome" or str end },
        },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress", total_lines },
        lualine_z = { "location" },
      },
    })
  end,
}
