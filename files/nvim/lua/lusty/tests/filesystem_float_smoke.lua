-- Filesystem float smoke: the serve-backed picker (lusty.native) end to
-- end. Runs headless like the other smokes:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_smoke.lua
-- Covers: initial listing, long view metadata (serve M), sort cycling
-- (serve Q sort token) and query filtering. Requires the lusty
-- binary on PATH (native.lua degrades with a notify when it is missing —
-- the test skips then).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal: the client ships F records and a stale real
-- journal would reorder the empty query.
require('lusty.frecency').set_state_file('/tmp/lusty_fs_smoke_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_smoke_frec.json')

local function assert_eq(got, want, msg)
  if got ~= want then
    error((msg or 'assert') .. ': got ' .. tostring(got) .. ' want ' .. tostring(want))
  end
end

local tmp = '/tmp/lusty_fs_smoke'
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
assert_eq(p.total, 3, 'depth-2 listing has 3 entries')
assert_eq(p.window[1].label, 'alpha.txt', 'default name order first')

-- Long view: metadata arrives via serve M for the visible rows.
p:handle('toggle_long')
assert(p.long, 'long view toggled on')
wait_until(function()
  for _, item in ipairs(p.window) do
    if item.meta == nil then
      return false
    end
  end
  return #p.window > 0
end, 'metadata on visible rows')
local alpha = nil
for _, item in ipairs(p.window) do
  if item.label == 'alpha.txt' then
    alpha = item
  end
end
assert(alpha, 'alpha.txt visible in long view')
assert(alpha.meta:match('^%-rw'), 'regular file perms in meta: ' .. alpha.meta)
assert(alpha.meta:match('%d%d%d%d%-%d%d%-%d%d'), 'date in meta: ' .. alpha.meta)
p:handle('toggle_long')
assert(not p.long, 'back to grid')

-- Sort cycle: ext groups the extensionless dir first.
p:handle('cycle_sort')
assert_eq(p.sort, 1, 'sort cycled to ext')
wait_until(function() return p.window[1] and p.window[1].label == 'subdir' end, 'ext order (no ext first)')
p:handle('cycle_sort') -- size
assert_eq(p.sort, 2)
p:handle('cycle_sort') -- time
assert_eq(p.sort, 3)
p:handle('cycle_sort') -- back to name
assert_eq(p.sort, 0)
wait_until(function() return p.window[1] and p.window[1].label == 'alpha.txt' end, 'name order restored')

-- Query filter: first letter must prefix the basename.
p:handle('b')
wait_until(function() return p.total == 1 and p.window[1] end, 'filter b')
assert_eq(p.window[1].label, 'beta.lua', 'b filters to beta.lua')
p:handle('cancel')

print('PASS filesystem float smoke')
vim.cmd('qa!')
