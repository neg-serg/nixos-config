-- Filesystem float AlwaysShowDotFiles smoke: g:LustyExplorerAlwaysShowDotFiles
-- keeps dotfiles visible from the start and typing a normal query must not
-- toggle them off. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_dots_smoke.lua
-- Requires the lusty binary on PATH (skips when it is missing).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('filesystem float dots smoke') then return end

-- Isolate the frecency journal (the client ships F records).
H.isolate_frecency('/tmp/lusty_fs_dots_frec.json')

local tmp = '/tmp/lusty_fs_dots_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'x' }, tmp .. '/.hidden')
vim.fn.writefile({ 'x' }, tmp .. '/visible.txt')

vim.g.LustyExplorerAlwaysShowDotFiles = 1
local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')

local wait_until = H.wait_until

local function labels()
  local out = {}
  for _, item in ipairs(p.window) do
    out[#out + 1] = item.label
  end
  return out
end

wait_until(function() return not p.loading end, 'first listing')
assert(p.show_dots, 'dots enabled from g:LustyExplorerAlwaysShowDotFiles')
assert(vim.tbl_contains(labels(), '.hidden'), 'dotfile listed: ' .. vim.inspect(labels()))

-- Typing must keep the option in force (the dot toggle follows the query).
p:handle('v')
wait_until(function() return p.total == 1 end, 'filter to visible.txt')
assert(p.show_dots, 'dots stay on while typing')
assert(vim.tbl_contains(labels(), 'visible.txt'), 'visible.txt matches')
p:handle('cancel')

H.finish('PASS filesystem float dots smoke')
