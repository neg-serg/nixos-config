-- Edit plugins: inc-rename, mini, suda
return {
  -- │ █▓▒░ smjonas/inc-rename.nvim                                                  │
  {
    "smjonas/inc-rename.nvim",
    cmd = "IncRename",
    keys = {
      { "<leader>rn", function() return ":IncRename " .. vim.fn.expand("<cword>") end, expr = true, desc = "Rename (inc-rename)" },
    },
    config = function()
      require("inc_rename").setup()
    end,
  },

  -- │ █▓▒░ echasnovski/mini.nvim                                                    │
  {
    'echasnovski/mini.nvim',
    event = 'VeryLazy',
    config = function()
      local map = vim.keymap.set
      local ok_align, align = pcall(require, 'mini.align')
      if ok_align then
        align.setup()
        map('x', 'ga', function() align.operator(align.gen_spec.input()) end, { desc = 'Align (visual)' })
        map('n', 'ga', function() align.operator(align.gen_spec.input()) end, { desc = 'Align (operator)' })
      end
      local ok_ts, trail = pcall(require, 'mini.trailspace')
      if ok_ts then trail.setup() end
      local ok_sj, sj = pcall(require, 'mini.splitjoin')
      if ok_sj then
        sj.setup()
        map('n', '<leader>a', function() sj.toggle() end, { desc = 'Split/Join toggle' })
      end
      local ok_sur, surround = pcall(require, 'mini.surround')
      if ok_sur then
        surround.setup({
          mappings = {
            add = 'cs', delete = 'ds', replace = 'ys',
            find = '', find_left = '', highlight = '',
            suffix_last = 'l', suffix_next = 'n',
          },
          respect_selection_type = true,
        })
        map('x', 'S', function() require('mini.surround').add('visual') end, { desc = 'Surround (visual)' })
        map('x', 'gS', function()
          vim.cmd('normal! gvV')
          require('mini.surround').add('visual')
        end, { desc = 'Surround (visual line)' })
        vim.keymap.set('n', 'cSS', 'cs_', { remap = true, desc = 'Surround current line' })
        vim.keymap.set('n', 'csw', 'csiw', { remap = true })
        vim.keymap.set('n', 'csW', 'csiW', { remap = true })
      end
      local ok_ai, ai = pcall(require, 'mini.ai')
      if ok_ai then ai.setup() end
    end,
  },

  -- │ █▓▒░ lambdalisue/suda.vim                                                     │
  {'lambdalisue/suda.vim', cmd = {'SudaRead', 'SudaWrite'}},

}
