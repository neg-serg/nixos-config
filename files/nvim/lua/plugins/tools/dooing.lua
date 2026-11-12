-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ atiladefreitas/dooing — todo list in a floating window                       │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'atiladefreitas/dooing',
  -- setup() installs the <leader>td/<leader>tD/<leader>tN maps and schedules the
  -- due-date check, so the plugin cannot be fully lazy; VeryLazy keeps it off the
  -- first screen. `cmd` covers the headless/scripted entry points.
  event = 'VeryLazy',
  cmd = { 'Dooing', 'DooingLocal', 'DooingDue' },
  opts = {
    -- Opt-in redesign: status sections, progress bar, tree guides for subtasks.
    ui = { style = 'modern' },
  },
}
