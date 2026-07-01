-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Wansmer/langmapper.nvim                                                      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'Wansmer/langmapper.nvim',
  event = 'VeryLazy',
  config = function()
    require('langmapper').setup({
        disable_hack_modes = {},
        automapping_modes = { 'n', 'v', 'x', 's', 'i' },
    })
  end,
}
