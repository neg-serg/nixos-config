-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-telescope/telescope.nvim                                                │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nvim-telescope/telescope.nvim',
  event = 'VeryLazy',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make', cond = function() return vim.fn.executable('make') == 1 end },
    { 'brookhong/telescope-pathogen.nvim', lazy = true },
    { 'jvgrootveld/telescope-zoxide', lazy = true },
    { 'nvim-telescope/telescope-frecency.nvim', lazy = true },
    { 'nvim-telescope/telescope-live-grep-args.nvim', lazy = true },
    { 'nvim-telescope/telescope-file-browser.nvim', lazy = true },
  },
  config = function()
    local telescope = require('telescope')
    local utils = require('utils.telescope')

    -- ---------- Helpers ----------
    local function lazy_call(mod, fn)
      return function(...)
        local ok, m = pcall(require, mod); if not ok then return end
        local f = m
        for name in tostring(fn):gmatch('[^%.]+') do
          f = f[name]; if not f then return end
        end
        return f(...) 
      end
    end
    local function act(name) return function(...) return require('telescope.actions')[name](...) end end
    local function builtin(name, opts) return function() return require('telescope.builtin')[name](opts or {}) end end

    local short_find = utils.best_find_cmd()

    -- ---------- Setup ----------
    local layout_actions = require('telescope.actions.layout')

    -- Fix: force dot to be a literal '.' inside Telescope prompt
    vim.api.nvim_create_autocmd('FileType', {
        pattern = 'TelescopePrompt',
        callback = function(ev)
            -- 1) Kill any insert-map on '.'
            pcall(vim.keymap.del, 'i', '.', { buffer = ev.buf })
            -- 2) Disable input method / lang remaps locally
            vim.opt_local.keymap = ''
            vim.opt_local.langmap = ''
            vim.opt_local.iminsert = 0
            vim.opt_local.imsearch = 0
            -- 3) Re-bind '.' to literal dot (expr+nowait to bypass remaps)
            vim.keymap.set('i', '.', function() return '.' end,
            { buffer = ev.buf, expr = true, nowait = true })
        end,
    })

    telescope.setup({
      defaults = {
        vimgrep_arguments = {
          'rg','--color=never','--no-heading','--with-filename',
          '--line-number','--column','--smart-case','--hidden',
          '--glob','!.git','--glob','!.obsidian',
          '--max-filesize','1M','--no-binary','--trim',
        },
        mappings = {
          i = {
            ['<esc>'] = act('close'),
            ['<C-u>'] = false,
            ['<C-s>'] = act('select_horizontal'),
            ['<C-v>'] = act('select_vertical'),
            ['<C-t>'] = act('select_tab'),
            -- send to qf + open
            ['<S-q>'] = function(...) local a=require('telescope.actions'); a.smart_send_to_qflist(...); return a.open_qflist(...) end,
            -- add to qf (keep picker)
            ['<C-q>'] = function(...) local a=require('telescope.actions'); a.smart_send_to_qflist(...); a.open_qflist(...) end,
            -- copy path variations
            ['<C-y>'] = (function()
              local function copier(kind)
                return function()
                  local e = require('telescope.actions.state').get_selected_entry(); if not e then return end
                  local p = e.path or e.value; if not p then return end
                  if kind == 'name' then p = vim.fn.fnamemodify(p, ':t')
                  elseif kind == 'rel' then p = vim.fn.fnamemodify(p, ':.')
                  else p = vim.fn.fnamemodify(p, ':p') end
                  vim.fn.setreg('+', p); vim.notify('Copied: ' .. p)
                end
              end
              return copier('abs')
            end)(),
            ['<A-y>'] = (function()
              local function copier(kind)
                return function()
                  local e = require('telescope.actions.state').get_selected_entry(); if not e then return end
                  local p = e.path or e.value; if not p then return end
                  if kind == 'name' then p = vim.fn.fnamemodify(p, ':t')
                  elseif kind == 'rel' then p = vim.fn.fnamemodify(p, ':.')
                  else p = vim.fn.fnamemodify(p, ':p') end
                  vim.fn.setreg('+', p); vim.notify('Copied: ' .. p)
                end
              end
              return copier('rel')
            end)(),
            ['<S-y>'] = (function()
              local function copier(kind)
                return function()
                  local e = require('telescope.actions.state').get_selected_entry(); if not e then return end
                  local p = e.path or e.value; if not p then return end
                  if kind == 'name' then p = vim.fn.fnamemodify(p, ':t')
                  elseif kind == 'rel' then p = vim.fn.fnamemodify(p, ':.')
                  else p = vim.fn.fnamemodify(p, ':p') end
                  vim.fn.setreg('+', p); vim.notify('Copied: ' .. p)
                end
              end
              return copier('name')
            end)(),
            ['<C-S-p>'] = layout_actions.toggle_preview,
          },
          n = {
            ['q'] = act('close'),
            ['<C-p>'] = layout_actions.toggle_preview,
          },
        },
        dynamic_preview_title = true,
        prompt_prefix = '❯> ',
        selection_caret = '• ',
        entry_prefix = '  ',
        initial_mode = 'insert',
        selection_strategy = 'reset',
        sorting_strategy = 'descending',
        layout_strategy = 'vertical',
        layout_config = { prompt_position = 'bottom', vertical = { width = 0.9, height = 0.9, preview_height = 0.6 } },
        file_ignore_patterns = utils.ignore_patterns,
        path_display = { truncate = 3 },
        winblend = 8,
        border = {},
        borderchars = { '─','│','─','│','╭','╮','╯','╰' },
        buffer_previewer_maker = utils.safe_buffer_previewer_maker,
        set_env = { COLORTERM = 'truecolor' },
        scroll_strategy = 'limit',
        wrap_results = true,
        history = { path = vim.fn.stdpath('state') .. '/telescope_history', limit = 200 },
      },

      pickers = {
        find_files = {
          theme = 'ivy', border = false, previewer = false,
          sorting_strategy = 'descending', prompt_title = false,
          find_command = short_find, layout_config = { height = 12 },
        },
        buffers = {
          sort_lastused = true, theme = 'ivy', previewer = false,
          mappings = { i = { ['<C-d>'] = act('delete_buffer') } },
        },
      },

      extensions = {
        fzf = { fuzzy = true, override_generic_sorter = true, override_file_sorter = true, case_mode = 'smart_case' },

        file_browser = {
          theme = 'ivy',
          border = true,
          prompt_title = false,
          grouped = true,
          hide_parent_dir = true,
          sorting_strategy = 'descending',
          layout_config = { height = 18 },
          hidden = { file_browser = false, folder_browser = false },
          hijack_netrw = false,
          git_status = false,

          mappings = {
            i = {
              ['<C-w>'] = function(prompt_bufnr, bypass)
                local state = require('telescope.actions.state')
                local picker = state.get_current_picker(prompt_bufnr)
                if picker and picker:_get_prompt() == '' then
                  local fb = require('telescope').extensions.file_browser.actions
                  return fb.goto_parent_dir(prompt_bufnr, bypass)
                else
                  local t = function(str) return vim.api.nvim_replace_termcodes(str, true, true, true) end
                  vim.api.nvim_feedkeys(t('<C-u>'), 'i', true)
                end
              end,
              -- FIX: use core select_default, not fb_actions.select_default
              ['<CR>']  = act('select_default'),
              ['<C-s>'] = act('select_horizontal'),
              ['<C-v>'] = act('select_vertical'),
              ['<C-t>'] = act('select_tab'),

              ['N'] = utils.fb_create_deep,   -- deep create file/dir
              ['Y'] = utils.fb_duplicate,     -- duplicate file
              ['='] = utils.fb_diff_two,      -- diff two selected
              ['H'] = utils.fb_diff_head,     -- diff vs HEAD

              -- keep existing:
              ['<C-.>'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_hidden(...) end,
              ['g.'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_respect_gitignore(...) end,
              ['<Tab>'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_selected(...) end,
              ['<S-Tab>'] = function(...) return require('telescope').extensions.file_browser.actions.select_all(...) end,
              ['<C-y>'] = function(prompt_bufnr)
                local entry = require('telescope.actions.state').get_selected_entry(); if not entry then return end
                local p = entry.path or entry.value; if not p then return end
                p = vim.fn.fnamemodify(p, ':p'); vim.fn.setreg('+', p); vim.notify('Path copied: ' .. p)
              end,
              ['<C-f>'] = function(prompt_bufnr)
                local state = require('telescope.actions.state')
                local picker = state.get_current_picker(prompt_bufnr)
                local cwd = (picker and picker._cwd) or vim.loop.cwd()
                require('telescope.builtin').find_files({ cwd = cwd, find_command = utils.best_find_cmd(), theme = 'ivy', previewer = false })
              end,
              ['<Esc>'] = act('close'),
            },
            n = {
              ['q'] = act('close'),
              ['gh'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_hidden(...) end,
              ['g.'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_respect_gitignore(...) end,
              ['N'] = utils.fb_create_deep,
              ['Y'] = utils.fb_duplicate,
              ['='] = utils.fb_diff_two,
              ['H'] = utils.fb_diff_head,
              ['<Tab>'] = function(...) return require('telescope').extensions.file_browser.actions.toggle_selected(...) end,
              ['<S-Tab>'] = function(...) return require('telescope').extensions.file_browser.actions.select_all(...) end,
              ['h'] = function(...) return require('telescope').extensions.file_browser.actions.goto_parent_dir(...) end,
              ['l'] = act('select_default'),
              ['s'] = act('select_horizontal'),
              ['v'] = act('select_vertical'),
              ['t'] = act('select_tab'),
              ['/'] = function() vim.cmd('startinsert') end,
            },
          },
        },

        pathogen = {
          use_last_search_for_live_grep = false,
          attach_mappings = function(map, acts)
            map('i', '<C-o>', acts.proceed_with_parent_dir)
            map('i', '<C-l>', acts.revert_back_last_dir)
            map('i', '<C-b>', acts.change_working_directory)
          end,
        },

        frecency = {
          disable_devicons = false,
          ignore_patterns = utils.ignore_patterns,
          path_display = { 'relative' },
          previewer = false,
          prompt_title = false,
          results_title = false,
          show_scores = false,
          show_unindexed = true,
          use_sqlite = true,
        },

        zoxide = {
          mappings = {
            ['<S-Enter>'] = { action = function(sel)
              local t = require('telescope'); pcall(t.load_extension, 'pathogen')
              t.extensions.pathogen.find_files({ cwd = sel.path })
            end },
            ['<Tab>'] = { action = function(sel)
              local t = require('telescope'); pcall(t.load_extension, 'pathogen')
              t.extensions.pathogen.find_files({ cwd = sel.path })
            end },
            ['<C-b>'] = {
              keepinsert = true,
              action = function(sel)
                local t = require('telescope'); pcall(t.load_extension, 'file_browser')
                t.extensions.file_browser.file_browser({ cwd = sel.path })
              end,
            },
            ['<C-f>'] = {
              keepinsert = true,
              action = function(sel)
                require('telescope.builtin').find_files({ cwd = sel.path, find_command = utils.best_find_cmd() })
              end,
            },
          },
        },

        live_grep_args = {
          auto_quoting = true,
          mappings = {
            i = {
              ['<C-k>'] = lazy_call('telescope-live-grep-args.actions', 'quote_prompt'),
              ['<C-i>'] = function() return require('telescope-live-grep-args.actions').quote_prompt({ postfix = ' --iglob ' })() end,
              ['<C-space>'] = lazy_call('telescope-live-grep-args.actions', 'to_fuzzy_refine'),
              ['<C-o>'] = function()
                local t = require('telescope'); pcall(t.load_extension, 'live_grep_args')
                t.extensions.live_grep_args.live_grep_args({ grep_open_files = true })
              end,
              ['<C-.>'] = function()
                local t = require('telescope'); pcall(t.load_extension, 'live_grep_args')
                t.extensions.live_grep_args.live_grep_args({ cwd = vim.fn.expand('%:p:h') })
              end,
              ['<C-g>'] = function()
                local a = require('telescope-live-grep-args.actions')
                return a.quote_prompt({ postfix = ' -g !**/node_modules/** -g !**/dist/** ' })()
              end,
              ['<C-t>'] = function()
                local a = require('telescope-live-grep-args.actions')
                return a.quote_prompt({ postfix = ' -t rust ' })()
              end,
              ['<C-p>'] = layout_actions.toggle_preview, -- also useful in LGA
            },
          },
        },
      },
    })

    -- ---------- Extensions ----------
    pcall(telescope.load_extension, 'fzf')
    vim.keymap.set('n', 'ee', utils.smart_files, opts)
    vim.keymap.set('n', '<leader>L', function()
      if vim.bo.filetype then pcall(function() require('oil.actions').cd.callback() end)
      else pcall(vim.cmd, 'ProjectRoot') end
      local t = require('telescope'); pcall(t.load_extension, 'pathogen')
      t.extensions.pathogen.find_files({})
    end, opts)
    
    vim.keymap.set('n', '<leader>l', function()
      local t = require('telescope')
      pcall(t.load_extension, 'file_browser')
      t.extensions.file_browser.file_browser({
        path = vim.fn.expand('%:p:h'),
        cwd = vim.fn.expand('%:p:h'),
        select_buffer = true,
      })
    end, opts)

    vim.keymap.set('n', '<leader>.', function()
      local t = require('telescope')
      pcall(t.load_extension, 'frecency')
      vim.cmd('Telescope frecency theme=ivy layout_config={height=12} sorting_strategy=descending')
    end, opts)

    -- TURBO mode
    vim.keymap.set('n', '<leader>sf', function() utils.turbo_find_files({ cwd = vim.fn.expand('%:p:h') }) end, opts)
    vim.keymap.set('n', '<leader>sF', function() utils.turbo_find_files({ cwd = utils.project_root() }) end, opts)
    vim.keymap.set('n', '<leader>sb', function() utils.turbo_file_browser({ cwd = vim.fn.expand('%:p:h') }) end, opts)

    -- Resume last picker
    vim.keymap.set('n', '<leader>sr', builtin('resume'), opts)

    -- Project helpers
    vim.keymap.set('n', 'gz', function()
      require('telescope.builtin').find_files({ cwd = vim.fn.expand('%:p:h'), find_command = utils.best_find_cmd(), theme = 'ivy', previewer = false })
    end, opts)

    -- Quickfix interaction
    vim.keymap.set('n', '<C-b>',  utils.qf_picker, opts)  -- Telescope quickfix picker (delete with "dd")
    vim.keymap.set('n', '<C-b>q', utils.qf_toggle, opts)  -- toggle quickfix window
    vim.keymap.set('n', '<C-b>d', utils.qf_clear, opts)   -- clear quickfix (d = delete)
    vim.keymap.set('n', '<C-b>a', function()
        vim.ui.input({ prompt = ':cdo ' }, function(cmd) if cmd and cmd ~= '' then utils.apply_cmd_to_qf(cmd) end end)
    end, opts)

    -- Missing keymaps restored
    vim.keymap.set('n', '<leader>sh', builtin('help_tags'), opts)
    vim.keymap.set('n', '<leader>sg', function()
      require('telescope.builtin').grep_string({ search = vim.fn.expand('<cword>') })
    end, opts)
    vim.keymap.set('n', 'cd', function()
      local t = require('telescope')
      pcall(t.load_extension, 'zoxide')
      t.extensions.zoxide.list(require('telescope.themes').get_ivy({ layout_config = { height = 8 }, border = false }))
    end, opts)
    vim.keymap.set('n', 'E', function()
      if vim.bo.filetype then pcall(function() require('oil.actions').cd.callback() end)
      else vim.cmd('chdir %:p:h') end
      local t = require('telescope'); pcall(t.load_extension, 'pathogen')
      t.extensions.pathogen.find_files({})
    end, opts)
  end,
}
