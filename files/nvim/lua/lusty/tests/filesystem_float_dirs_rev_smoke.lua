-- Filesystem float dirs-first/reverse smoke: verifies the serve-backed
-- picker requests Q with dirs_first/reverse flags when the matching
-- option is enabled (g:LustyExplorerDirsFirst / g:LustyExplorerReverse).
-- Runs headless like the other smokes.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('filesystem float dirs/rev smoke') then return end

-- Isolate the frecency journal: the client ships F records and a stale real
-- journal would reorder the empty query.
H.isolate_frecency('/tmp/lusty_fs_dirs_rev_frec.json')

local tmp = '/tmp/lusty_fs_dirs_rev_smoke'
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'hello' }, tmp .. '/alpha.txt')
vim.fn.writefile({ 'hello world' }, tmp .. '/beta.lua')
vim.fn.writefile({ 'fn main(){}' }, tmp .. '/gamma.rs')
vim.fn.mkdir(tmp .. '/zeta_dir', 'p')

local native = require('lusty.native')

local wait_until = H.wait_until

local function labels(p)
  local out = {}
  for _, item in ipairs(p.window) do
    out[#out + 1] = item.label
  end
  return out
end

-- dirs_first: the directory leads the canonical name order.
vim.g.LustyExplorerDirsFirst = 1
vim.g.LustyExplorerReverse = false
local p = native.run(tmp)
assert(p, 'picker opens')
wait_until(function() return p.window and #p.window > 0 end, 'rows dirs-first')
wait_until(function() return p.window[1] and p.window[1].label == 'zeta_dir' end, 'dir first')
assert(p.window[1].label == 'zeta_dir', 'zeta_dir first, got ' .. tostring(p.window[1] and p.window[1].label))
p:handle('cancel')

-- reverse: canonical [alpha,beta,gamma,zeta] becomes [zeta,gamma,beta,alpha].
vim.g.LustyExplorerDirsFirst = false
vim.g.LustyExplorerReverse = 1
local p2 = native.run(tmp)
assert(p2, 'second picker opens')
wait_until(function() return p2.window and #p2.window > 0 end, 'rows reverse')
wait_until(function()
  local ls = labels(p2)
  return #ls == 4 and ls[1] == 'zeta_dir' and ls[4] == 'alpha.txt'
end, 'reversed depth group')
assert(labels(p2)[1] == 'zeta_dir', 'reverse puts zeta_dir first')
assert(labels(p2)[4] == 'alpha.txt', 'reverse puts alpha.txt last')
p2:handle('cancel')

H.finish('PASS filesystem float dirs/rev smoke')
