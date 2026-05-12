return {
  'rebelot/heirline.nvim',
  lazy = false,
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('plugins.panel.heirline.config')()
  end,
}
