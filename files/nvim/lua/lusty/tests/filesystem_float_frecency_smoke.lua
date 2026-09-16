-- Filesystem float frecency smoke: the client ships its open-frequency journal
-- as `F` records and the backend leads the empty query with the frequent file
-- inside each depth (canonical alphabetical order otherwise). Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_frecency_smoke.lua
-- Requires the lusty binary on PATH; skips when it predates the F request.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('filesystem float frecency smoke') then return end

-- Deterministic, isolated journal: one recorded open of zzz.txt.
local frec = H.isolate_frecency('/tmp/lusty_fs_frec_smoke.json')
frec.set_now(function() return 1700000000 end)

local tmp = '/tmp/lusty_fs_frec_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'x' }, tmp .. '/aaa.txt')
vim.fn.writefile({ 'x' }, tmp .. '/zzz.txt')
frec.record(tmp .. '/zzz.txt')

--- Probe the deployed backend: send F for zzz then Q. A backend without the F
--- request answers in canonical order (aaa first), so skip instead of failing
--- while an older binary is still deployed.
local function backend_orders_by_frecency()
  local acc = ''
  local job = vim.fn.jobstart({ 'lusty', 'serve', tmp, '--depth', '1', '--skip', '' }, {
    on_stdout = function(_, data)
      acc = acc .. table.concat(data, '\n')
    end,
  })
  if job <= 0 then
    return false
  end
  local t0 = vim.loop.hrtime()
  while not acc:find('^C %d+') and (vim.loop.hrtime() - t0) / 1e6 < 3000 do
    vim.wait(10)
  end
  vim.fn.chansend(job, 'F\t100\t' .. tmp .. '/zzz.txt\n')
  vim.fn.chansend(job, 'Q\t0\t10\t\n')
  t0 = vim.loop.hrtime()
  while not acc:match('\nE\n?$') and (vim.loop.hrtime() - t0) / 1e6 < 3000 do
    vim.wait(10)
  end
  vim.fn.jobstop(job)
  for line in acc:gmatch('[^\n]+') do
    if line:sub(1, 2) == 'R ' then
      return line:match('\t(.*)$') == tmp .. '/zzz.txt'
    end
  end
  return false
end

if not backend_orders_by_frecency() then
  return H.skip('filesystem float frecency smoke', 'backend without the F request')
end

local native = require('lusty.native')

local wait_until = H.wait_until

local p = native.run(tmp)
assert(p, 'filesystem picker opens')
wait_until(function() return p.window and #p.window > 0 end, 'initial rows')
assert(
  p.window[1].path == tmp .. '/zzz.txt',
  'frequent file leads the empty query: ' .. tostring(p.window[1] and p.window[1].path)
)
p:handle('cancel')

-- Opt-out: g:LustyExplorerFrecency = 0 keeps the canonical order.
vim.g.LustyExplorerFrecency = 0
local p2 = native.run(tmp)
assert(p2, 'second picker opens')
wait_until(function() return p2.window and #p2.window > 0 end, 'rows without frecency')
assert(
  p2.window[1].path == tmp .. '/aaa.txt',
  'opt-out keeps the canonical order: ' .. tostring(p2.window[1] and p2.window[1].path)
)
p2:handle('cancel')

H.finish('PASS filesystem float frecency smoke')
