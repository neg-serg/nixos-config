-- │ █▓▒░ y3owk1n/time-machine.nvim                                              │
-- Interactive undo history tree with diffs/bookmarks/cleanup.
-- Lazy-load on commands and leader keymaps.
return {
  "y3owk1n/time-machine.nvim",
  version = "*",

  cmd = {
    "TimeMachineToggle",
    "TimeMachinePurgeBuffer",
    "TimeMachinePurgeAll",
    "TimeMachineLogShow",
    "TimeMachineLogClear",
  },
  keys = {
    { '<leader>ut', '<cmd>TimeMachineToggle<cr>', desc = 'Time Machine: toggle' },
  },
  opts = {
    -- Keep defaults; we already use persistent undo in settings
    -- You can set diff_tool = 'difft' if you have it installed
  },
}
