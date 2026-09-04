-- Native float smoke: regression for lusty.native_pick and the pickers that
-- use it (buffers, buffer grep, recent). Runs headless like smoke.lua:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/native_float_smoke.lua
-- Floating windows work headless; keys are driven through Picker:handle.

local base = vim.fn.fnamemodify(arg[0], ':p:h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local function assert_eq(got, want, msg)
  if got ~= want then
    error((msg or 'assert') .. ': got ' .. tostring(got) .. ' want ' .. tostring(want))
  end
end

local function mk_listed(name, lines)
  local b = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(b, name)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  return b
end

local pick = require('lusty.native_pick')

-- ---------------------------------------------------------------------------
-- Buffer explorer: MRU list, current rotated last, filter, C-d delete, close.
local bs = require('lusty.buffer_stack')
local a = mk_listed('/tmp/alpha.lua', { 'line one', 'alpha beta' })
local b = mk_listed('/tmp/beta.md', { 'beta line' })
local c = mk_listed('/tmp/gamma.txt', { 'gamma' })
vim.cmd('buffer ' .. c) -- make gamma the current buffer
bs.reset()

local nbufs = require('lusty.native_buffers')
nbufs.run()
local p = pick.active_pick()
assert(p, 'buffers picker opens')
assert_eq(p.total, 4, 'buffers total (3 + [No Name])')
assert_eq(p.items[#p.items].bufnr, c, 'current buffer rotated to the end')
-- first-letter filter
p:handle('b')
assert_eq(p.total, 1, 'query b filters to beta')
assert_eq(p.items[1].bufnr, b, 'filter picks beta')
-- back to full list and delete one
p:handle('clear')
p.selected = 0
local victim = p.items[1].bufnr
p:handle('delete')
assert_eq(p.total, 3, 'C-d removes one buffer')
assert_eq(vim.fn.buflisted(victim), 0, 'deleted buffer is unlisted')
p:handle('cancel')
assert(pick.active_pick() == nil, 'cancel closes the picker')
print('PASS native buffer explorer')

-- ---------------------------------------------------------------------------
-- Buffer grep: empty pattern lists buffers, typing greps, marks present.
local ngrep = require('lusty.native_buffer_grep')
ngrep.run()
p = pick.active_pick()
assert(p, 'grep picker opens')
assert_eq(p.total, 3, 'empty grep pattern lists the remaining buffers')
p:handle('a')
p:handle('l')
p:handle('p')
assert(p.total >= 1, 'grep finds alpha matches')
local hit = p.items[1]
assert_eq(hit.line, 2, 'match line is 2')
assert(hit.marks and #hit.marks == 4, 'match row has sub-highlights')
p:handle('cancel')
print('PASS native buffer grep')

-- ---------------------------------------------------------------------------
-- Recent files: injected source, dedupe, missing files skipped, filter.
local tmp = '/tmp/lusty_nfs_recent'
vim.fn.mkdir(vim.fn.fnamemodify(tmp, ':h'), 'p')
vim.fn.writefile({ 'x' }, tmp .. '.md')
local nrecent = require('lusty.native_recent')
nrecent.set_recent_fn(function()
  return { tmp .. '.md', tmp .. '.md', tmp .. '.gone', '/etc/nixos/flake.nix' }
end)
nrecent.run()
p = pick.active_pick()
assert(p, 'recent picker opens')
assert_eq(p.total, 2, 'recent dedupes and drops missing files')
assert_eq(p.items[1].path, tmp .. '.md', 'most recent first')
p:handle('f')
assert_eq(p.total, 1, 'filter by basename first letter')
assert_eq(p.items[1].path, '/etc/nixos/flake.nix', 'filters to flake.nix')
p:handle('cancel')
print('PASS native recent files')

-- ---------------------------------------------------------------------------
-- Query memory: the last filter is restored on the next run.
nbufs.run()
p = pick.active_pick()
p:handle('g')
p:handle('cancel')
nbufs.run()
p = pick.active_pick()
assert_eq(p.query, 'g', 'buffers picker restores the last query')
p:handle('cancel')
print('PASS native query memory')

print('ALL NATIVE FLOAT SMOKE TESTS PASSED')
vim.cmd('qa!')
