-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ brenoprata10/nvim-highlight-colors                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'brenoprata10/nvim-highlight-colors', -- highlight colors
  ft = { "css", "html", "javascript", "typescript", "javascriptreact", "typescriptreact", "json", "yaml", "python" },
  config=function() require('nvim-highlight-colors').setup({}) end
}
