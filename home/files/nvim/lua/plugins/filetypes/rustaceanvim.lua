-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mrcjkb/rustaceanvim                                                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'mrcjkb/rustaceanvim',
  version = '^6',
  ft = { 'rust' },
  init = function()
    local function on_attach(_, bufnr)
      local function map(lhs, rhs, desc)
        vim.keymap.set('n', lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
      end

      map('K', function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust hover actions')
    end

    vim.g.rustaceanvim = {
      tools = {
        test_executor = 'neotest',
        code_actions = { ui_select_fallback = true },
      },
      server = {
        on_attach = on_attach,
        default_settings = {
          ['rust-analyzer'] = {
            cargo = { buildScripts = { enable = true } },
            procMacro = { enable = true },
          },
        },
      },
      dap = { autoload_configurations = true },
    }
  end,
}
