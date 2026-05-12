-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Tsuzat/NeoSolarized.nvim                                                     │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'Tsuzat/NeoSolarized.nvim',
  lazy = true,
  priority = 870,
  opts = function()
    local transparent = vim.g.transparent_window == true

    return {
      style = 'dark',
      transparent = transparent,
      terminal_colors = true,
      enable_italics = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = { bold = true },
        variables = {},
        string = { italic = false },
        underline = false,
        undercurl = true,
      },
      on_highlights = function(highlights)
        local cursorline = vim.tbl_extend('force', {}, highlights.CursorLine or {})
        cursorline.underline = false
        highlights.CursorLine = cursorline
      end,
    }
  end,
  config = function(_, opts)
    local ok, neosolarized = pcall(require, 'NeoSolarized'); if not ok then return end
    neosolarized.setup(opts)
    vim.cmd('colorscheme NeoSolarized')
  end,
}
