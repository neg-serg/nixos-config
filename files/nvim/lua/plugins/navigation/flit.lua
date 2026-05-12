-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ ggandor/flit.nvim                                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'ggandor/flit.nvim',
  dependencies = { 'ggandor/leap.nvim' },
  keys = {
    { 'f', mode = { 'n', 'x', 'o' }, desc = 'Flit f' },
    { 'F', mode = { 'n', 'x', 'o' }, desc = 'Flit F' },
    { 't', mode = { 'n', 'x', 'o' }, desc = 'Flit t' },
    { 'T', mode = { 'n', 'x', 'o' }, desc = 'Flit T' },
  },
  opts = {
    labeled_modes = 'nv', -- show labels in Normal/Visual
    multiline = true,
  },
}

