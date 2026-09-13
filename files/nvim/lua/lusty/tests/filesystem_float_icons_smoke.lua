-- Filesystem float icons smoke: verifies the serve-backed picker renders
-- nerd-font icons in the grid and prompt when g:LustyExplorerIcons = 1.
-- Runs headless like the other smokes:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_icons_smoke.lua

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float icons smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal: the client ships F records and a stale real
-- journal would reorder the empty query.
require('lusty.frecency').set_state_file('/tmp/lusty_fs_icons_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_icons_frec.json')

vim.g.LustyExplorerIcons = 1

local tmp = '/tmp/lusty_fs_icons_smoke'
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'hello' }, tmp .. '/alpha.txt')
vim.fn.writefile({ 'hello world' }, tmp .. '/beta.lua')
vim.fn.mkdir(tmp .. '/subdir', 'p')

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

wait_until(function() return p.window and #p.window > 0 end, 'initial rows')

local dir_icon = vim.fn.nr2char(0xf115)
local file_icon = vim.fn.nr2char(0xf15b)
wait_until(function()
  local lines = vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
  local all = table.concat(lines, '\n')
  return all:find(dir_icon, 1, true) and all:find(file_icon, 1, true)
end, 'icons rendered in float buffer')

print('PASS filesystem float icons smoke')
p:handle('cancel')
vim.cmd('qa!')
