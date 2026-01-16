-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ craftzdog/solarized-osaka.nvim                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'craftzdog/solarized-osaka.nvim',
  lazy = true,
  priority = 900,
  opts = function()
    local transparent = vim.g.transparent_window == true
    return {
      transparent = transparent,
      styles = {
        sidebars = transparent and 'transparent' or 'default',
        floats = transparent and 'transparent' or 'default',
      },
      on_highlights = function(highlights, palette)
        local cursor_bg = palette.bg_highlight or palette.bg or '#1b1d1e'
        local cursorline = highlights.CursorLine or {}
        cursorline.bg = cursor_bg
        cursorline.underline = false
        highlights.CursorLine = cursorline
      end,
    }
  end,
  config = function(_, opts)
    local ok, solarized = pcall(require, 'solarized-osaka'); if not ok then return end
    solarized.setup(opts)
  end,
}
