-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Prgebish/partial-completion.nvim                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'Prgebish/partial-completion.nvim', -- Emacs-style partial completion for paths, Ex commands and cmdline
  event = { "BufReadPre", "BufNewFile", "CmdlineEnter" },
  dependencies = { 'saghen/blink.cmp' }, -- blink provider is wired in completion/blink.lua
  config = function()
    -- Defaults; the native cmdline UI stays disabled because blink.cmp owns the menu.
    require('partial_completion').setup({})
  end,
}
