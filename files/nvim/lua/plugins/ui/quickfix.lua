-- │ █▓▒░ Santhosh-tekuri/quickfix.nvim                                           │
-- Enhances quickfix list rendering (column-range highlights, sane defaults).
-- No setup table; just wire quickfixtextfunc.
return {
  'Santhosh-tekuri/quickfix.nvim',
  event = { 'QuickFixCmdPre', 'QuickFixCmdPost' },
  config = function()
    vim.o.quickfixtextfunc = require('quickfix').quickfixtextfunc
  end,
}

