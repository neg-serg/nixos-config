-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ ficd0/ashen.nvim                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'ficd0/ashen.nvim',
  version = '*',
  lazy = true,
  priority = 840,
  opts = function()
    local transparent = vim.g.transparent_window == true

    return {
      variant = 'default',
      style_presets = {
        bold_functions = true,
        italic_comments = true,
      },
      transparent = transparent,
      terminal = {
        enabled = not transparent,
        colors = {},
      },
      plugins = {
        autoload = true,
        override = {},
      },
    }
  end,
  config = function(_, opts)
    local ok, ashen = pcall(require, 'ashen'); if not ok then return end
    ashen.setup(opts)
    ashen.load()
  end,
}
