return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    local state = require("config.state")
    local win_utils = require("config.windows")
    local builtin = require("telescope.builtin")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local from_entry = require("telescope.from_entry")
    local putils = require("telescope.previewers.utils")

    -- Telescope's default git_status previewer pipes `git diff` into a buffer
    -- with filetype=diff, so only the +/-/@@ structure gets colored and the
    -- underlying PHP stays plain. This previewer instead loads the REAL file
    -- content with its real filetype -- so treesitter colors the code exactly
    -- like every other view -- and then marks the changed lines with gutter
    -- signs (+ = added, ~ = changed; blue) plus a faint line tint, derived
    -- from `git diff -U0`. Code coloring is never touched, only the gutter.
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
            -- Real filetype -> treesitter attaches and colors the code.
            local ft = vim.filetype.match({ filename = path }) or ""
            if ft ~= "" then
              vim.bo[bnr].filetype = ft
              pcall(vim.treesitter.start, bnr, ft)
            end
            -- Overlay change markers from `git diff -U0` (blue gutter signs).
            -- Run git from the file's own directory so the repo is found
            -- regardless of Telescope's cwd.
            local dir = vim.fn.fnamemodify(path, ":h")
            vim.system(
              { "git", "-C", dir, "diff", "-U0", "--", path },
              { text = true },
              function(res)
                if not res.stdout then return end
                -- Parse each hunk header. Format: @@ -old,oldN +new,newN @@
                -- oldN/newN default to 1 when the ",N" part is absent. The
                -- +side describes the CURRENT file (what we're previewing):
                --   newN > 0, oldN == 0  -> pure addition
                --   newN > 0, oldN > 0   -> changed lines
                --   newN == 0            -> pure deletion (mark the line above)
                local signs = {}
                for oldc, newstart, newc in res.stdout:gmatch(
                  "@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@"
                ) do
                  local old_n = oldc == "" and 1 or tonumber(oldc)
                  local new_s = tonumber(newstart)
                  local new_n = newc == "" and 1 or tonumber(newc)
                  if new_n == 0 then
                    -- deletion: git reports +N,0 -> lines removed after line N
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
                    -- In-text change marker: tint the changed line's whole
                    -- background the same translucent blue as the in-buffer
                    -- word-diff (GitSignsAddInline = #22384f). Deletes have no
                    -- line in the current file, so they get no line tint.
                    if s.kind ~= "TelescopeGsDelete" and s.lnum >= 1 and s.lnum <= last then
                      pcall(vim.api.nvim_buf_set_extmark, bnr, gs_hl_ns, s.lnum - 1, 0,
                        { line_hl_group = "GitSignsAddInline" })
                    end
                    if not first or s.lnum < first then first = s.lnum end
                  end
                  -- Line numbers + scroll so the FIRST change is centered in
                  -- view (full file + coloring kept, but the change is what
                  -- you land on -- like the old @@-hunk preview did).
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

    -- Telescope was never given a setup() call, so every picker ran on the
    -- built-in defaults: layout_strategy="horizontal" sized as a PERCENTAGE of
    -- the window it's invoked over, and a preview_cutoff of 80 that silently
    -- drops the preview in narrow windows. Invoked from the blame column or a
    -- vertical split, that produced a small picker with the buffer still
    -- visible around it instead of one big window.
    --
    -- Pin the layout so a picker looks identical no matter which window has
    -- focus when it opens: near-fullscreen, centered, preview always on.
    local full_layout = {
      layout_strategy = "horizontal",
      layout_config = {
        -- Fractions of the total EDITOR size, not the current window: these
        -- are what make the picker ignore which split it was opened from.
        width  = 0.9,
        height = 0.9,
        -- 0 = never fall back to the no-preview layout.
        preview_cutoff = 0,
        -- Strategy-specific keys MUST stay nested under their strategy. A
        -- top-level layout_config key is merged into EVERY strategy, and a
        -- strategy that doesn't recognise a key hard-errors on it rather than
        -- ignoring it -- so one stray default breaks other plugins' pickers:
        --   preview_width   -> rejected by "center" (what themes.get_dropdown
        --                      uses, e.g. leetcode.nvim's `:Leet lang`)
        --   prompt_position -> rejected by "cursor"
        -- Only "horizontal" is our own strategy, so that's the only one to
        -- configure; themed pickers bring their own values.
        horizontal = {
          preview_width = 0.55,
          prompt_position = "bottom",
        },
      },
      -- "descending" is what pairs with a bottom prompt: best match sits
      -- closest to where you're typing.
      sorting_strategy = "descending",
    }

    require("telescope").setup({ defaults = full_layout })

    local function open_in_main(prompt_bufnr)
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if not entry then return end
      local path = entry.path or entry.filename or entry.value or entry[1]
      if not path then return end
      -- Tear down the blame column before routing the file in, so the file can
      -- never land in the (narrow, nofile) blame window.
      pcall(function() require("config.blame").close() end)
      local main = win_utils.find_main_window()
      if main then vim.api.nvim_set_current_win(main) end
      vim.cmd("edit " .. vim.fn.fnameescape(path))
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

    vim.keymap.set("n", "<leader>ff", function()
      builtin.find_files({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Find files" })

    vim.keymap.set("n", "<leader>fg", function()
      builtin.live_grep({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Live grep" })

    vim.keymap.set("n", "<leader>fw", function()
      builtin.grep_string({ attach_mappings = with_action(open_in_main) })
    end, { desc = "Grep word under cursor" })

    -- Buffers picker. The default builtin.buffers is fiddly: depending on the
    -- picker's own options it can hide the current buffer, hide unnamed/hidden
    -- ones, and sort by "last used" so the list order jumps around whenever you
    -- switch files -- which is why with several buffers open it sometimes came
    -- up empty or missing entries. Pin every knob to a fixed, predictable view:
    -- always list every real file buffer (never terminals/tree/blame), show the
    -- current one, and keep a stable order so it looks the same every time.
    vim.keymap.set("n", "<leader>fb", function()
      builtin.buffers({
        attach_mappings = with_action(open_in_main),
        show_all_buffers = true,   -- include hidden (not-yet-displayed) buffers
        ignore_current_buffer = false,
        sort_mru = false,          -- stable order, not "most recently used"
        sort_lastused = false,
        only_cwd = false,
      })
    end, { desc = "Buffers" })

    vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })

    vim.keymap.set("n", "<leader>gs", function()
      builtin.git_status({
        previewer = git_status_previewer,
        attach_mappings = with_action(open_in_main),
      })
    end, { desc = "Git changed files" })

    -- Published so lsp.lua's `gr` can reuse the same "open in the main window"
    -- routing as the pickers above instead of duplicating the window logic.
    require("config.picker").open_in_main = with_action(open_in_main)

    vim.keymap.set("n", "<leader>fd", function()
      builtin.find_files({
        find_command = { "find", ".", "-type", "d", "-not", "-path", "*/.git*" },
        prompt_title = "Find Directories",
        attach_mappings = with_action(reveal_dir),
      })
    end, { desc = "Find directories" })
  end,
}
