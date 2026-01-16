-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-neotest/neotest                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    'mrcjkb/rustaceanvim',
  },
  event = { 'BufReadPost', 'BufNewFile' },
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
