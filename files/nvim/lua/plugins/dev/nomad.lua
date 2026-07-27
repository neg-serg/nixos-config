-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nomad/nomad — collaborative editing                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nomad/nomad',
  build = 'cargo xtask neovim build --release',
  cmd = { 'Mad' },
  keys = {
    { '<leader>ms', '<cmd>Mad collab start<cr>', desc = 'Nomad: start session' },
    { '<leader>mj', '<cmd>Mad collab join<cr>', desc = 'Nomad: join session' },
    { '<leader>ml', '<cmd>Mad collab leave<cr>', desc = 'Nomad: leave session' },
    { '<leader>mu', '<cmd>Mad collab users<cr>', desc = 'Nomad: list users' },
  },
}
