-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ NTBBloodbath/sweetie.nvim                                                    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'NTBBloodbath/sweetie.nvim',
  lazy = true,
  priority = 850,
  config = function()
    local transparent = vim.g.transparent_window == true

    vim.g.sweetie = vim.tbl_deep_extend('force', vim.g.sweetie or {}, {
      pumblend = {
        enable = not transparent,
        transparency_amount = 20,
      },
      terminal_colors = true,
      cursor_color = true,
      overrides = {
        Comment = { italic = true },
        Keyword = { italic = true },
      },
      integrations = vim.tbl_deep_extend('force', {}, (vim.g.sweetie or {}).integrations or {}, {
        lazy = true,
        telescope = true,
        neogit = true,
      }),
    })

    if transparent then
      vim.g.sweetie.terminal_colors = false
      vim.g.sweetie.cursor_color = false
    end

    local ok, sweetie = pcall(require, 'sweetie'); if not ok then return end
    sweetie.set()
    vim.cmd.colorscheme('sweetie')
  end,
}
