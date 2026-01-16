-- │ █▓▒░ bassamsdata/namu.nvim                                                   │
-- Symbols/workspace/diagnostics picker with live preview and order-preserving
-- filtering. Installs with safe defaults; expose a few non-conflicting keys.
return {
  'bassamsdata/namu.nvim',
  cmd = { 'Namu' },
  opts = {
    -- Keep module defaults; enable symbols module
    namu_symbols = { enable = true, options = {} },
  },
  keys = {
    { '<leader>ns', '<cmd>Namu symbols<cr>',    desc = '[Namu] Symbols (buffer)' },
    { '<leader>nw', '<cmd>Namu workspace<cr>',  desc = '[Namu] Symbols (workspace)' },
    { '<leader>nd', '<cmd>Namu diagnostics<cr>', desc = '[Namu] Diagnostics' },
    { '<leader>nh', '<cmd>Namu help<cr>',       desc = '[Namu] Help' },
  },
}

