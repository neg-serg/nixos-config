-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ chrisgrieser/nvim-various-textobjs                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'chrisgrieser/nvim-various-textobjs',
  event = { 'BufReadPost', 'BufNewFile' },
  opts = {
    useDefaultKeymaps = true,
    disabledKeymaps = {},
  },
}
