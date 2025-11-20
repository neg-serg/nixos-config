-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ eldritch-theme/eldritch.nvim                                                 │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'eldritch-theme/eldritch.nvim',
  lazy = true,
  priority = 890,
  opts = function()
    local transparent = vim.g.transparent_window == true
    local sidebar_style = transparent and 'transparent' or 'dark'

    return {
      transparent = transparent,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
        sidebars = sidebar_style,
        floats = sidebar_style,
      },
      sidebars = { 'qf', 'help', 'neo-tree', 'lazy', 'toggleterm' },
      hide_inactive_statusline = false,
      dim_inactive = false,
      lualine_bold = true,
      on_highlights = function(highlights)
        local cursorline = vim.tbl_extend('force', {}, highlights.CursorLine or {})
        cursorline.underline = false
        highlights.CursorLine = cursorline
      end,
    }
  end,
  config = function(_, opts)
    local ok, eldritch = pcall(require, 'eldritch'); if not ok then return end
    eldritch.setup(opts)
  end,
}
