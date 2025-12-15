-- │ █▓▒░ y3owk1n/time-machine.nvim                                              │
-- Interactive undo history tree with diffs/bookmarks/cleanup.
-- Lazy-load on commands and leader keymaps.
return {
  "y3owk1n/time-machine.nvim",
  version = "*",
  enabled = false, -- disabled via HM request: remove Neovim TimeMachine
  cmd = {
    "TimeMachineToggle",
    "TimeMachinePurgeBuffer",
    "TimeMachinePurgeAll",
    "TimeMachineLogShow",
    "TimeMachineLogClear",
  },
  keys = {},
  opts = {
    -- Keep defaults; we already use persistent undo in settings
    -- You can set diff_tool = 'difft' if you have it installed
  },
}
