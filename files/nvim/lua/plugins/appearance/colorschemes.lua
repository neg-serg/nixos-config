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
    build = ':TSUpdate',
    config = function()
      require('nvim-treesitter.config').setup({
        ensure_installed = {
          'bash', 'c', 'cpp', 'cmake', 'css', 'dockerfile', 'dot',
          'go', 'haskell', 'html', 'json', 'jsonc', 'lua', 'luadoc', 'make',
          'markdown', 'markdown_inline', 'nix', 'python', 'regex', 'rust', 'toml',
          'typescript', 'vim', 'vimdoc', 'yaml',
        },
        auto_install = true, -- auto-install parsers for new filetypes so nothing is left unhighlighted
        highlight = { enable = true },
        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = '<C-space>',
            node_incremental = '<C-space>',
            node_decremental = '<BS>',
          },
        },
      })
    end,
  },
}
