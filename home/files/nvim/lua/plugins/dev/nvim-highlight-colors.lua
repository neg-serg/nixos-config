-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ brenoprata10/nvim-highlight-colors                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'brenoprata10/nvim-highlight-colors', -- highlight colors
  event = { "BufReadPost", "BufNewFile" },
  config=function() require('nvim-highlight-colors').setup({}) end
}
