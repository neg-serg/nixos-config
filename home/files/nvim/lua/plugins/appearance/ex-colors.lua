-- │ █▓▒░ aileot/ex-colors.nvim                                                   │
-- Extract current highlight definitions and generate a fast ex-<scheme>.
-- Provides :ExColors to write a colorscheme under stdpath('config')/colors.
return {
  'aileot/ex-colors.nvim',
  cmd = { 'ExColors' },
  opts = {
    -- Use sane defaults; outputs to ~/.config/nvim/colors by default.
    -- You can fine‑tune included/excluded groups later if needed.
  },
}

