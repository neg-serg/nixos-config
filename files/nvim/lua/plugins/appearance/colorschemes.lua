-- Appearance plugins (excluding neg.nvim colorscheme which has its own spec)
return {
  -- │ █▓▒░ aileot/ex-colors.nvim                                                   │
  -- Extract current highlight definitions and generate a fast ex-<scheme>.
  {
    'aileot/ex-colors.nvim',
    cmd = { 'ExColors' },
    opts = {},
  },

  -- │ █▓▒░ nvim-treesitter/nvim-treesitter                                           │
  {
    'nvim-treesitter/nvim-treesitter',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('nvim-treesitter').setup()
      -- Incremental selection: expand/shrink visual selection by syntax tree
      vim.keymap.set('n', '<C-space>', function()
        require('nvim-treesitter.incremental_selection').init_selection()
      end, { desc = 'TS: init selection' })
      vim.keymap.set('x', '<C-space>', function()
        require('nvim-treesitter.incremental_selection').node_incremental()
      end, { desc = 'TS: expand selection' })
      vim.keymap.set('x', '<BS>', function()
        require('nvim-treesitter.incremental_selection').node_decremental()
      end, { desc = 'TS: shrink selection' })
    end,
  },
}
