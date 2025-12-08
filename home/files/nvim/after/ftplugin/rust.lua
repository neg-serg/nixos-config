local buf = vim.api.nvim_get_current_buf()

local function map(lhs, rhs, desc)
  vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, desc = desc })
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
map('K', function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust hover actions')
