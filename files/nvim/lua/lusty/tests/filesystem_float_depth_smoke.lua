-- Filesystem float runtime-depth smoke: C-d cycles the search depth 1..6 and
-- the listing follows (depth 1 hides subdirectory files), and the new depth
-- survives the picker restart. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_depth_smoke.lua
-- Requires the lusty binary on PATH (skips when it is missing).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float depth smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal (the client ships F records).
local frec = require('lusty.frecency')
frec.set_state_file('/tmp/lusty_fs_depth_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_depth_frec.json')

local tmp = '/tmp/lusty_fs_depth_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp .. '/sub', 'p')
vim.fn.writefile({ 'x' }, tmp .. '/alpha.txt')
vim.fn.writefile({ 'x' }, tmp .. '/sub/deep.txt')

vim.g.LustyExplorerSearchDepth = 1
local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')
assert(p.depth == 1, 'initial depth comes from g:LustyExplorerSearchDepth')

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

wait_until(function() return p.window and #p.window > 0 end, 'rows at depth 1')
assert(p.total == 2, 'depth 1 lists the dir and the file only, got ' .. tostring(p.total))

-- C-d bumps the depth in place (a new picker object takes over) and the listing
-- then includes the nested file.
local p2 = p:cycle_depth()
assert(p2, 'cycle_depth returns the new picker')
assert(p2.depth == 2, 'depth cycled to 2, got ' .. tostring(p2.depth))
wait_until(function() return p2.total == 3 end, 'depth 2 includes sub/deep.txt')
assert(p2.total == 3, 'depth 2 lists the nested file, got ' .. tostring(p2.total))

-- The cycle wraps 6 -> 1.
local q = p2
for _, want in ipairs({ 3, 4, 5, 6, 1 }) do
  q = q:cycle_depth()
  assert(q.depth == want, 'depth ' .. want .. ', got ' .. tostring(q.depth))
end
q:handle('cancel')

print('PASS filesystem float depth smoke')
vim.cmd('qa!')
