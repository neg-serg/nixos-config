-- Filesystem float C-e smoke: the typed text is treated as a path, the parent
-- directories are created and the path opens as a new buffer; the file itself
-- appears on :w only. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_create_smoke.lua
-- Requires the lusty binary on PATH (skips when it is missing).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float create smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal (the client ships F records).
local frec = require('lusty.frecency')
frec.set_state_file('/tmp/lusty_fs_create_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_create_frec.json')

local tmp = '/tmp/lusty_fs_create_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')

local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')

local function wait_until(cond, what, ms)
  ms = ms or 5000
  local t0 = vim.loop.hrtime()
  while not cond() do
    if (vim.loop.hrtime() - t0) / 1e6 > ms then
      error('timeout waiting for ' .. what)
    end
    vim.wait(10)
  end
end

-- The fixture root is empty on purpose; wait for the first backend answer.
wait_until(function() return not p.loading end, 'first listing')

-- C-e with a nested relative path: parents are created, the path becomes the
-- current buffer and nothing is written to disk yet.
p.query = 'sub/dir/new.txt'
p:handle('create')
assert(vim.fn.isdirectory(tmp .. '/sub/dir') == 1, 'parent directories created')
assert(vim.fn.filereadable(tmp .. '/sub/dir/new.txt') == 0, 'file is created on :w, not on C-e')
local name = vim.api.nvim_buf_get_name(0)
assert(name == tmp .. '/sub/dir/new.txt', 'created path is the current buffer: ' .. name)

-- An empty query is a no-op with a warning; the picker stays open.
local p2 = native.run(tmp)
assert(p2, 'second picker opens')
wait_until(function() return not p2.loading end, 'second listing')
p2.query = ''
p2:handle('create')
assert(not p2.closed, 'empty C-e keeps the picker open')
p2:handle('cancel')

print('PASS filesystem float create smoke')
vim.cmd('qa!')
