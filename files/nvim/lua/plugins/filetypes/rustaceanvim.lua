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

      map('<leader>rr', function() vim.cmd.RustLsp('runnables') end, 'Rust runnables')
      map('<leader>rR', function() vim.cmd.RustLsp({ 'runnables', bang = true }) end, 'Rust rerun last runnable')
      map('<leader>rd', function() vim.cmd.RustLsp('debuggables') end, 'Rust debuggables')
      map('<leader>rt', function() vim.cmd.RustLsp('testables') end, 'Rust testables')
      map('<leader>re', function() vim.cmd.RustLsp('explainError') end, 'Rust explain error')
      map('<leader>rD', function() vim.cmd.RustLsp('renderDiagnostic') end, 'Rust render diagnostic')
      map('<leader>ra', function() vim.cmd.RustLsp('codeAction') end, 'Rust code actions')
      map('<leader>rl', function() vim.cmd.RustLsp('relatedDiagnostics') end, 'Rust related diagnostics')
      map('<leader>rk', function() vim.cmd.RustLsp({ 'flyCheck', 'run' }) end, 'Rust fly check run')
      map('<leader>rK', function() vim.cmd.RustLsp({ 'flyCheck', 'clear' }) end, 'Rust fly check clear')
      map('<leader>ro', function() vim.cmd.RustLsp('openDocs') end, 'Rust open docs.rs')
      map('<leader>rC', function() vim.cmd.RustLsp('openCargo') end, 'Rust open Cargo.toml')
      map('<leader>rS', function()
        local query = vim.fn.input('workspace symbol: ')
        if query == nil then return end
        vim.cmd.RustLsp({ 'workspaceSymbol', 'allSymbols', query, bang = true })
      end, 'Rust workspace symbol (with deps)')
      map('<leader>rg', function() vim.cmd.RustLsp('crateGraph') end, 'Rust crate graph')
      map('<leader>rv', function()
        local view = vim.fn.input('view hir/mir: ')
        if view == nil or view == '' then return end
        vim.cmd.RustLsp({ 'view', view })
      end, 'Rust view HIR/MIR')
      map('<leader>ru', function()
        local kind = vim.fn.input('rustc unpretty (hir/mir/...): ')
        if kind == nil or kind == '' then return end
        vim.cmd.Rustc({ 'unpretty', kind })
      end, 'Rustc unpretty')
      map('<leader>rp', function() vim.cmd.RustLsp('rebuildProcMacros') end, 'Rust rebuild proc macros')
      map('<leader>rM', function() vim.cmd.RustLsp('parentModule') end, 'Rust parent module')
      map('<leader>rH', function() vim.cmd.RustLsp({ 'hover', 'range' }) end, 'Rust hover range')
      map('<leader>rA', function()
        local cfg = vim.fn.input('rust-analyzer config (Lua table): ')
        if cfg == nil or cfg == '' then return end
        vim.cmd.RustAnalyzer({ 'config', cfg })
      end, 'RustAnalyzer config')
      map('<leader>rT', function()
        local tgt = vim.fn.input('rust-analyzer target (empty = default): ')
        if tgt == nil then return end
        if tgt == '' then
          vim.cmd.RustAnalyzer('target')
        else
          vim.cmd.RustAnalyzer({ 'target', tgt })
        end
      end, 'RustAnalyzer target')
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
