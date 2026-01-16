-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ cshuaimin/ssr.nvim                                                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'cshuaimin/ssr.nvim',
  keys = {
    {
      '<leader>fr',
      function() require('ssr').open() end,
      mode = { 'n', 'x' },
      desc = '[F]ind [R]eplace (structural)',
    },
  },
  opts = {
    border = 'rounded',
    min_width = 50,
    min_height = 5,
    max_width = 120,
    max_height = 25,
  },
}

