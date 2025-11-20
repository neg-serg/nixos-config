-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ ggandor/flit.nvim                                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'ggandor/flit.nvim',
  dependencies = { 'ggandor/leap.nvim' },
  opts = {
    labeled_modes = 'nv', -- show labels in Normal/Visual
    multiline = true,
  },
  config = function(_, opts)
    require('flit').setup(opts)
  end,
}

