return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    -- Native fzf sorter: faster, and supports 'exact / ^prefix / !not queries.
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  config = function()
    local state = require("config.state")
    local win_utils = require("config.windows")
    local builtin = require("telescope.builtin")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local from_entry = require("telescope.from_entry")
    local putils = require("telescope.previewers.utils")

    -- git_status previewer: instead of the default ft=diff pipe (structure
    -- colored, code plain), load the real file with its real filetype so
    -- treesitter colors it, and overlay change markers from `git diff -U0`
    -- as gutter signs plus a faint line tint.
    vim.fn.sign_define("TelescopeGsAdd",    { text = "+", texthl = "GitSignsAdd" })
    vim.fn.sign_define("TelescopeGsChange", { text = "~", texthl = "GitSignsChange" })
    vim.fn.sign_define("TelescopeGsDelete", { text = "_", texthl = "GitSignsDelete" })
    local gs_hl_ns = vim.api.nvim_create_namespace("TelescopeGsLineHl")

    local git_status_previewer = previewers.new_buffer_previewer({
      title = "Git Changes",
      get_buffer_by_name = function(_, entry)
        return from_entry.path(entry, false)
      end,
      define_preview = function(self, entry)
        local path = from_entry.path(entry, false)
        if not path or path == "" then return end
        local bufnr = self.state.bufnr

        putils.job_maker({ "cat", path }, bufnr, {
          value = path,
          bufname = self.state.bufname,
          callback = function(bnr)
            if not vim.api.nvim_buf_is_valid(bnr) then return end
            local ft = vim.filetype.match({ filename = path }) or ""
            if ft ~= "" then
              vim.bo[bnr].filetype = ft
              pcall(vim.treesitter.start, bnr, ft)
            end
            -- Run git from the file's own directory so the repo is found
            -- regardless of Telescope's cwd.
            local dir = vim.fn.fnamemodify(path, ":h")
            vim.system(
              { "git", "-C", dir, "diff", "-U0", "--", path },
              { text = true },
              function(res)
                if not res.stdout then return end
                -- Hunk headers: @@ -old,oldN +new,newN @@ (N defaults to 1).
                -- The + side describes the current file: oldN==0 -> addition,
                -- both >0 -> change, newN==0 -> deletion (mark line above).
                local signs = {}
                for oldc, newstart, newc in res.stdout:gmatch(
                  "@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@"
                ) do
                  local old_n = oldc == "" and 1 or tonumber(oldc)
                  local new_s = tonumber(newstart)
                  local new_n = newc == "" and 1 or tonumber(newc)
                  if new_n == 0 then
                    signs[#signs + 1] = { lnum = math.max(new_s, 1), kind = "TelescopeGsDelete" }
                  else
                    local kind = old_n > 0 and "TelescopeGsChange" or "TelescopeGsAdd"
                    for l = new_s, new_s + new_n - 1 do
                      signs[#signs + 1] = { lnum = l, kind = kind }
                    end
                  end
                end
                vim.schedule(function()
                  if not vim.api.nvim_buf_is_valid(bnr) then return end
                  local last = vim.api.nvim_buf_line_count(bnr)
                  local first
                  vim.api.nvim_buf_clear_namespace(bnr, gs_hl_ns, 0, -1)
                  for _, s in ipairs(signs) do
                    pcall(vim.fn.sign_place, 0, "TelescopeGs", s.kind, bnr,
                      { lnum = s.lnum, priority = 100 })
                    -- Line tint matches the in-buffer word-diff blue. Deletes
                    -- have no line in the current file, so no tint.
                    if s.kind ~= "TelescopeGsDelete" and s.lnum >= 1 and s.lnum <= last then
                      pcall(vim.api.nvim_buf_set_extmark, bnr, gs_hl_ns, s.lnum - 1, 0,
                        { line_hl_group = "GitSignsAddInline" })
                    end
                    if not first or s.lnum < first then first = s.lnum end
                  end
                  -- Land centered on the first change, numbers + signs on.
                  local win = self.state and self.state.winid
                  if win and vim.api.nvim_win_is_valid(win) then
                    vim.wo[win].number = true
                    vim.wo[win].signcolumn = "yes"
                    if first then
                      pcall(vim.api.nvim_win_set_cursor, win, { math.min(first, last), 0 })
                      vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
                    end
                  end
                end)
              end
            )
          end,
        })
      end,
    })

    -- Pin the layout so a picker looks identical no matter which window has
    -- focus when it opens: near-fullscreen, centered, preview always on.
    -- (The builtin defaults size as a percentage of the CURRENT window and
    -- drop the preview below 80 columns -- tiny pickers from narrow splits.)
    local full_layout = {
      layout_strategy = "horizontal",
      layout_config = {
        width  = 0.9,   -- fractions of the total editor size
        height = 0.9,
        preview_cutoff = 0,   -- never fall back to the no-preview layout
        -- Strategy-specific keys MUST stay nested under their strategy: a
        -- top-level key is merged into EVERY strategy, and strategies
        -- hard-error on keys they don't recognise (center rejects
        -- preview_width, cursor rejects prompt_position) -- which breaks
        -- other plugins' themed pickers, e.g. leetcode's dropdowns.
        horizontal = {
          preview_width = 0.55,
          prompt_position = "bottom",
        },
      },
      -- Pairs with a bottom prompt: best match closest to where you type.
      sorting_strategy = "descending",
    }

    require("telescope").setup({ defaults = full_layout })
    -- pcall: a failed `make` leaves telescope's own sorter in place.
    pcall(require("telescope").load_extension, "fzf")

    local function open_in_main(prompt_bufnr)
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if not entry then return end
      local path = entry.path or entry.filename or entry.value or entry[1]
      if not path then return end
      -- Tear down the blame column first so the file can never land in it.
      pcall(function() require("config.blame").close() end)
      local main = win_utils.find_main_window()
      if main then vim.api.nvim_set_current_win(main) end
      -- Already the current file (symbols, diagnostics, same-file references):
      -- :edit would re-read it and fail on unsaved changes (E37).
      if vim.fn.fnamemodify(path, ":p") ~= vim.api.nvim_buf_get_name(0) then
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      end
      if entry.lnum then
        pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, (entry.col or 1) - 1 })
      end
    end

    local function reveal_dir(prompt_bufnr)
      local entry = action_state.get_selected_entry()
      if not entry then return end
      local raw = entry.path or entry.value or entry[1]
      if not raw then return end
      local abs = vim.fn.fnamemodify(raw, ":p")
      actions.close(prompt_bufnr)
      vim.defer_fn(function()
        state.building = true
        local main = win_utils.find_main_window()
        if main and vim.api.nvim_win_is_valid(main) then
          vim.api.nvim_set_current_win(main)
        end
        pcall(function()
          require("nvim-tree.api").tree.find_file({ buf = abs, focus = true, open = true })
        end)
        state.building = false
      end, 50)
    end

    local function with_action(action)
      return function(_, _)
        actions.select_default:replace(action)
        return true
      end
    end

    -- Published for lsp.lua's `gr`, so it reuses the same routing.
    require("config.picker").open_in_main = with_action(open_in_main)

    vim.keymap.set("n", "<leader>ff", function()
      builtin.find_files({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Find files" })

    vim.keymap.set("n", "<leader>fg", function()
      builtin.live_grep({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Live grep" })

    vim.keymap.set("n", "<leader>fw", function()
      builtin.grep_string({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Grep word under cursor" })

    -- Every knob pinned to a fixed, predictable view: all real file buffers,
    -- current one included, stable order (the defaults hide/sort-by-MRU,
    -- which made the list jump around or come up missing entries).
    vim.keymap.set("n", "<leader>fb", function()
      builtin.buffers({
        attach_mappings = with_action(open_in_main),
        show_all_buffers = true,
        ignore_current_buffer = false,
        sort_mru = false,
        sort_lastused = false,
        only_cwd = false,
      })
    end, { desc = "Buffers" })

    vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })

    vim.keymap.set("n", "<leader>fd", function()
      builtin.find_files({
        find_command = { "find", ".", "-type", "d", "-not", "-path", "*/.git*" },
        prompt_title = "Find Directories",
        attach_mappings = with_action(reveal_dir),
      })
    end, { desc = "Find directories" })

    vim.keymap.set("n", "<leader>fs", function()
      builtin.lsp_document_symbols({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Symbols in this file" })

    vim.keymap.set("n", "<leader>fS", function()
      builtin.lsp_dynamic_workspace_symbols({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Symbols in the project" })

    vim.keymap.set("n", "<leader>fe", function()
      builtin.diagnostics({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Diagnostics (all open buffers)" })

    -- Opens in normal mode, unlike the find pickers: this is a list of the
    -- files you changed, not a search. You arrive to read it and move down it
    -- with hjkl -- typing would only filter a list you can already see. `i`
    -- still drops into the prompt when the list is long enough to want it.
    vim.keymap.set("n", "<leader>gs", function()
      builtin.git_status({
        initial_mode = "normal",
        previewer = git_status_previewer,
        attach_mappings = with_action(open_in_main),
      })
    end, { desc = "Git changed files" })
  end,
}
