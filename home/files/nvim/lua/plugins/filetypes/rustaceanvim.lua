-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mrcjkb/rustaceanvim                                                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'mrcjkb/rustaceanvim',
  version = '^6',
  ft = { 'rust' },
  init = function()
    vim.g.rustaceanvim = {
      tools = {
        test_executor = 'background',
        code_actions = { ui_select_fallback = true },
      },
      dap = { autoload_configurations = true },
    }
  end,
}
