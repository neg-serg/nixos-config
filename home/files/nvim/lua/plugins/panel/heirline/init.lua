return {
  'rebelot/heirline.nvim',
  event = "UIEnter",
  lazy = true,
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    require('plugins.panel.heirline.config')()
  end,
}
