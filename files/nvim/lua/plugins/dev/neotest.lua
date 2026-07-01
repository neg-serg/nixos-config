-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-neotest/neotest                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    'mrcjkb/rustaceanvim',
  },
  cmd = { 'Neotest' },
  keys = {
    { '<leader>tt', function() require('neotest').run.run() end, desc = 'Run nearest test' },
    { '<leader>tf', function() require('neotest').run.run(vim.fn.expand('%')) end, desc = 'Run file' },
    { '<leader>ts', function() require('neotest').summary.toggle() end, desc = 'Summary' },
    { '<leader>to', function() require('neotest').output.open() end, desc = 'Output' },
  },
  config = function()
    local ok, neotest = pcall(require, 'neotest')
    if not ok then return end
    neotest.setup({
      adapters = {
        require('rustaceanvim.neotest'),
      },
    })
  end,
}
