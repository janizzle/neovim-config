return {
  "nvim-lualine/lualine.nvim",
  dependencies = "nvim-tree/nvim-web-devicons",
  config = function()
    -- Active window only: a component can't tell which window it draws for,
    -- so in inactive_sections this would show the current buffer's count.
    local function total_lines()
      return vim.api.nvim_buf_line_count(0) .. " lines"
    end

    -- Names of the language servers attached to this buffer (php -> intelephense).
    local function lsp_clients()
      local names = {}
      for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do names[#names + 1] = c.name end
      return #names > 0 and table.concat(names, ", ") or ""
    end

    require("lualine").setup({
      options = { theme = "auto", section_separators = "", component_separators = "" },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        -- fmt relabels only the start screen ("[No Name]" -> "Welcome");
        -- modified/readonly flags keep working.
        -- aerial: breadcrumbs, the class › method the cursor is in.
        lualine_c = {
          { "filename", fmt = function(str) return vim.b.welcome_screen and "Welcome" or str end },
          "aerial",
        },
        lualine_x = { "encoding", "fileformat", "filetype", { lsp_clients, icon = "" } },
        lualine_y = { "progress", total_lines },
        lualine_z = { "location" },
      },
    })
  end,
}
