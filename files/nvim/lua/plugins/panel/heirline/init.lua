return {
  'rebelot/heirline.nvim',
  event = 'UIEnter',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('plugins.panel.heirline.config')()
  end,
}
