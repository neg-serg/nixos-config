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
    -- setup() only wraps vim.keymap.set calls made *after* it. Mappings that
    -- already exist by then get no RU twins: every lazy.nvim `keys` stub is
    -- created at startup, and snacks (priority 1000) loads before langmapper
    -- at VeryLazy. automapping() walks the current global maps once and adds
    -- the twins for them; later mappings keep coming from hack_keymap.
    require('langmapper').automapping({ global = true, buffer = false })
  end,
}
