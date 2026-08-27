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
      -- Safe extra modules: no overlap with existing plugins (heirline, noice,
      -- blink.cmp, which-key, gitsigns, yazi/fff, LuaSnip, leap, Comment.nvim).
      local ok_anim, anim = pcall(require, 'mini.animate')
      if ok_anim then anim.setup() end
      local ok_mv, mv = pcall(require, 'mini.move')
      if ok_mv then
        mv.setup()
        map('n', '<M-Up>', function() mv.move_line('up') end, { desc = 'Move line up' })
        map('n', '<M-Down>', function() mv.move_line('down') end, { desc = 'Move line down' })
        map('x', '<M-Up>', function() mv.move_selection('up') end, { desc = 'Move selection up' })
        map('x', '<M-Down>', function() mv.move_selection('down') end, { desc = 'Move selection down' })
      end
      local ok_iscope, iscope = pcall(require, 'mini.indentscope')
      if ok_iscope then iscope.setup() end
      local ok_br, br = pcall(require, 'mini.bufremove')
      if ok_br then br.setup() end
      local ok_op, op = pcall(require, 'mini.operators')
      if ok_op then op.setup() end
      local ok_cw, cw = pcall(require, 'mini.cursorword')
      if ok_cw then cw.setup() end
      local ok_hp, hp = pcall(require, 'mini.hipatterns')
      if ok_hp then hp.setup() end
    end,
  },

  -- │ █▓▒░ lambdalisue/suda.vim                                                     │
  {'lambdalisue/suda.vim', cmd = {'SudaRead', 'SudaWrite'}},

}
