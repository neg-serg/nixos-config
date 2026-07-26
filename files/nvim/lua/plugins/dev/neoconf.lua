return {
  'folke/neoconf.nvim',
  cmd = 'Neoconf',
  opts = { import = { vim.fn.stdpath('config') .. '/.neoconf' } },
  config = function(_, opts)
    require('neoconf').setup(opts)
  end,
}
