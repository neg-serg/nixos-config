-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ gisketch/triforce.nvim — RPG gamification for Neovim                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'gisketch/triforce.nvim',
  dependencies = { 'nvzone/volt' },
  keys = {
    { '<leader>tp', function() require('triforce').show_profile() end, desc = 'Triforce: profile' },
  },
  opts = {},
}
