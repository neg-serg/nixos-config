return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    preset = 'modern',
    delay = 400,
    spec = {},
  },
  keys = {
    { '<leader>?', function() require('which-key').show({ global = false }) end, desc = 'Buffer Keymaps' },
  },
}
