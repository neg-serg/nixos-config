-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ shaunsingh/moonlight.nvim                                                   │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'shaunsingh/moonlight.nvim',
  lazy = true,
  priority = 880,
  config = function()
    local transparent = vim.g.transparent_window == true

    vim.g.moonlight_italic_comments = true
    vim.g.moonlight_italic_keywords = true
    vim.g.moonlight_italic_functions = false
    vim.g.moonlight_italic_variables = false
    vim.g.moonlight_borders = false
    vim.g.moonlight_contrast = not transparent
    vim.g.moonlight_disable_background = transparent

    local ok, moonlight = pcall(require, 'moonlight'); if not ok then return end
    moonlight.set()

    -- Keep cursorline styling aligned with other themes
    vim.api.nvim_set_hl(0, 'CursorLine', { underline = false })
  end,
}
