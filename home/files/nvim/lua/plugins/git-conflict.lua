-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ akinsho/git-conflict.nvim                                                   │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- Minimal git conflict helper: defaults on, uses quickfix for the list opener.
return {
  "akinsho/git-conflict.nvim", -- merge conflict helper with inline highlights
  version = "*",               -- track tagged releases instead of main
  config = function()
    require("git-conflict").setup({
      default_mappings = true,     -- keep default keymaps
      default_commands = true,     -- keep default :GitConflict* commands
      disable_diagnostics = false, -- keep LSP diagnostics visible
      list_opener = "copen",       -- open conflict list via quickfix
      highlights = {
        incoming = "DiffAdd",
        current = "DiffText",
        -- ancestor = "DiffChange", -- enable if ancestor blocks are needed
      },
    })
  end,
}
