-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Chaitanyabsprip/fastaction.nvim                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'Chaitanyabsprip/fastaction.nvim',
  keys = {
    { 'eq', function() require('fastaction').code_action() end, mode = { 'n', 'x' }, desc = 'Code action (fastaction)' },
  },
  opts = {},
}
