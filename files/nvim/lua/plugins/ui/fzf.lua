-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ ibhagwan/fzf-lua                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'ibhagwan/fzf-lua',
  cmd = { 'FzfLua' },
  keys = {
    { 'ee', function() require('utils.fzf').smart_files() end, desc = 'Smart find files' },
    { '<leader>l', function()
      require('fzf-lua').files({ cwd = vim.fn.expand('%:p:h') })
    end, desc = 'Files in current dir' },
    { '<leader>L', function()
      require('fzf-lua').files({ cwd = require('utils.fzf').project_root() })
    end, desc = 'Files in project root' },
    { '<leader>.', function() require('utils.fzf').frecency() end, desc = 'Frecent files' },
    { '<leader>sf', function()
      require('utils.fzf').turbo_find({ cwd = vim.fn.expand('%:p:h') })
    end, desc = 'Turbo find (cwd)' },
    { '<leader>sF', function()
      require('utils.fzf').turbo_find({ cwd = require('utils.fzf').project_root() })
    end, desc = 'Turbo find (root)' },
    { '<leader>sb', function()
      require('fzf-lua').files({
        cwd = vim.fn.expand('%:p:h'),
        winopts = { height = 0.5, width = 1, row = 1 },
      })
    end, desc = 'File browser (cwd)' },
    { '<leader>sr', function() require('fzf-lua').resume() end, desc = 'Resume last picker' },
    { '<leader>sh', function() require('fzf-lua').helptags() end, desc = 'Help tags' },
    { '<leader>sg', function() require('fzf-lua').grep_cword() end, desc = 'Grep word under cursor' },
    { 'gz', function()
      require('fzf-lua').files({ cwd = vim.fn.expand('%:p:h') })
    end, desc = 'Find in dir' },
    { 'cd', function() require('fzf-lua').zoxide() end, desc = 'Zoxide dirs' },
    { 'E', function()
      require('fzf-lua').files({ cwd = require('utils.fzf').project_root() })
    end, desc = 'Project root find' },
    { '<C-b>', function() require('fzf-lua').quickfix() end, desc = 'Quickfix picker' },
    { '<C-b>q', function() require('utils.fzf').qf_toggle() end, desc = 'QF toggle' },
    { '<C-b>d', function() require('utils.fzf').qf_clear() end, desc = 'QF clear' },
    { '<C-b>a', function()
      vim.ui.input({ prompt = ':cdo ' }, function(cmd)
        if cmd and cmd ~= '' then require('utils.fzf').apply_cmd_to_qf(cmd) end
      end)
    end, desc = 'Apply cmd to QF' },
  },
  config = function()
    local fzf = require('fzf-lua')
    local actions = require('fzf-lua.actions')

    fzf.setup({
      winopts = {
        height = 0.5, width = 1, row = 1,
        border = 'none',
        winblend = 8,
        preview = {
          default = 'builtin',
          layout = 'vertical',
          vertical = 'up:60%',
          title = true,
          title_pos = 'center',
          winopts = { winblend = 8 },
        },
      },
      fzf_opts = {
        ['--layout'] = 'reverse-list',
        ['--prompt'] = '❯ ',
        ['--pointer'] = '•',
        ['--marker'] = '•',
        ['--separator'] = '─',
        ['--info'] = 'inline-right',
        ['--exact'] = '',
        ['--cycle'] = '',
        ['--no-scrollbar'] = '',
        ['--no-mouse'] = '',
      },
      fzf_colors = true,
      keymap = {
        fzf = {
          ['ctrl-q'] = 'select-all+accept',
          ['alt-p'] = 'toggle-preview',
          ['alt-a'] = 'select-all',
          ['ctrl-space'] = 'select-all',
        },
      },
      actions = {
        files = {
          ['default'] = actions.file_edit,
          ['ctrl-s'] = actions.file_split,
          ['ctrl-v'] = actions.file_vsplit,
          ['ctrl-t'] = actions.file_tabedit,
          ['alt-q'] = actions.file_sel_to_qf,
        },
      },
      files = {
        fd_opts = '-H --ignore-vcs --strip-cwd-prefix --type f',
        rg_opts = '--files --hidden --iglob !.git',
        git_icons = false,
        file_icons = true,
        previewer = false,
      },
      buffers = {
        sort_lastused = true,
        previewer = false,
        actions = {
          ['ctrl-d'] = { fn = actions.buf_del, reload = true },
        },
      },
      grep = {
        winopts = { height = 0.75 },
        rg_opts = '--column --line-number --no-heading --color=always --smart-case --hidden --glob !.git --glob !.obsidian --max-filesize 1M --no-binary --trim',
      },
      oldfiles = {
        winopts = { height = 0.25 },
        previewer = false,
      },
    })
  end,
}
