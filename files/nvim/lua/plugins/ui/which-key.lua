return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  opts = {
    preset = 'modern',
    delay = 400,
    spec = {},
    -- Only auto-trigger on the leader prefix. The <auto> default makes
    -- which-key intercept every key that starts some mapping chain (e.g.
    -- 'c' via the 'cd' zoxide map), which delayed plain letters inside the
    -- Lusty pickers (the reported delayed-c issue).
    triggers = {
      { '<leader>', mode = 'nxso' },
    },
  },
  keys = {
    { '<leader>?', function() require('which-key').show({ global = false }) end, desc = 'Buffer Keymaps' },
  },
}
