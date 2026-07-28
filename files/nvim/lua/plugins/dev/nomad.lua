-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nomad/nomad — collaborative editing (disabled: needs Rust build)              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nomad/nomad',
  enabled = false, -- requires nightly Rust + internet: cd plugin-dir && cargo xtask neovim build --release
  keys = {
    { '<leader>ms', '<cmd>Mad collab start<cr>', desc = 'Nomad: start session' },
    { '<leader>mj', '<cmd>Mad collab join<cr>', desc = 'Nomad: join session' },
    { '<leader>ml', '<cmd>Mad collab leave<cr>', desc = 'Nomad: leave session' },
    { '<leader>mu', '<cmd>Mad collab users<cr>', desc = 'Nomad: list users' },
  },
}
