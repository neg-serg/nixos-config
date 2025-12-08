local buf = vim.api.nvim_get_current_buf()

local function map(lhs, rhs, desc)
  vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, desc = desc })
end

map('<leader>rr', function() vim.cmd.RustLsp('runnables') end, 'Rust runnables')
map('<leader>rR', function() vim.cmd.RustLsp({ 'runnables', bang = true }) end, 'Rust rerun last runnable')
map('<leader>rd', function() vim.cmd.RustLsp('debuggables') end, 'Rust debuggables')
map('<leader>rt', function() vim.cmd.RustLsp('testables') end, 'Rust testables')
map('<leader>re', function() vim.cmd.RustLsp('explainError') end, 'Rust explain error')
map('K', function() vim.cmd.RustLsp({ 'hover', 'actions' }) end, 'Rust hover actions')
