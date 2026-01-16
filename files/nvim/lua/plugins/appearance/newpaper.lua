-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ yorik1984/newpaper.nvim                                                      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'yorik1984/newpaper.nvim',
  lazy = true,
  priority = 860,
  opts = function()
    local transparent = vim.g.transparent_window == true

    return {
      style = 'dark',
      editor_better_view = true,
      terminal = transparent and 'inverse_transparent' or 'contrast',
      sidebars_contrast = { 'qf', 'help', 'neo-tree', 'lazy', 'toggleterm' },
      contrast_float = true,
      contrast_telescope = true,
      operators_bold = true,
      delimiters_bold = false,
      brackets_bold = false,
      booleans = 'bold',
      keywords = 'bold',
      doc_keywords = 'bold,italic',
      regex = 'bold',
      regex_bg = true,
      italic_strings = true,
      italic_comments = true,
      italic_doc_comments = true,
      italic_functions = false,
      italic_variables = false,
      borders = not transparent,
      disable_background = transparent,
      lsp_virtual_text_bg = not transparent,
      hide_eob = false,
      lualine_bold = true,
    }
  end,
  config = function(_, opts)
    local ok, newpaper = pcall(require, 'newpaper'); if not ok then return end
    newpaper.setup(opts)
    vim.cmd('colorscheme newpaper')
  end,
}
