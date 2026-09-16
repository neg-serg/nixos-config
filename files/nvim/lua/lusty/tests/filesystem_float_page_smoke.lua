-- Filesystem float page smoke: the first Q cannot know `total` yet, so the
-- backend page used to cover a single column of the grid; once the total is
-- known the grid may want more columns and the picker has to re-ask for the
-- full page instead of leaving the lower rows empty. Runs headless like the
-- other smokes:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_page_smoke.lua
-- Requires the lusty binary on PATH (the test skips without it).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('filesystem float page smoke') then return end

-- Isolate the frecency journal: a stale real one would reorder the listing.
H.isolate_frecency('/tmp/lusty_fs_page_smoke_frec.json')

local tmp = '/tmp/lusty_fs_page_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
for i = 1, 40 do
  vim.fn.writefile({ 'x' }, string.format('%s/bulk%02d.txt', tmp, i))
end

local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')

local wait_until = H.wait_until

wait_until(function() return p.total == 40 end, 'total known')
-- The grid must be filled: every visible position carries an entry, so the
-- fetched page covers list_rows() * max_cols() slots (or all 40 entries).
wait_until(function()
  return #p.window == math.min(p:screen_count(), p.total)
end, 'page fills the grid')
assert(p:max_cols() > 1, 'grid uses more than one column')
assert(#p.window > p:list_rows(), 'page is wider than the first single column')

H.finish('PASS filesystem float page smoke')
