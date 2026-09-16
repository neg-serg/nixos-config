-- Native float smoke: regression for lusty.native_pick and the pickers that
-- use it (buffers, buffer grep, recent). Runs headless like smoke.lua:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/native_float_smoke.lua
-- Floating windows work headless; keys are driven through Picker:handle.

local base = vim.fn.fnamemodify(arg[0], ':p:h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

local assert_eq = H.assert_eq

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

-- ---------------------------------------------------------------------------
-- Frecency: recorded files outrank plain oldfiles order.
local frec = require('lusty.frecency')
local stfile = '/tmp/lusty_nfs_frec.json'
pcall(vim.fn.delete, stfile)
frec.set_state_file(stfile)
frec.set_now(function() return 1700000000 end)
frec.record('/etc/nixos/flake.nix')
frec.record('/etc/nixos/flake.nix')
frec.record('/tmp/lusty_nfs_recent.md')
local nr2 = require('lusty.native_recent')
nr2.set_recent_fn(function() return { '/tmp/lusty_nfs_recent.md', '/etc/nixos/flake.nix' } end)
nr2.run()
p = pick.active_pick()
p:handle('clear') -- ignore remembered query
assert_eq(p.items[1].path, '/etc/nixos/flake.nix', 'frecency file ranks first')
p:handle('cancel')

-- MRU merges the journal: with no injected source the recent picker must
-- list files that exist only in the frecency journal (v:oldfiles is empty
-- in a headless run), ranked by frecency score.
nr2.set_recent_fn(nil)
nr2.run()
p = pick.active_pick()
p:handle('clear')
assert(p.total >= 2, 'journal entries merged into MRU, got ' .. tostring(p.total))
assert_eq(p.items[1].path, '/etc/nixos/flake.nix', 'journal-only entry ranks first by frecency')
p:handle('cancel')

-- Dirs MRU: recorded directory visits (filesystem-float Enter on a dir)
-- appear in the dirs mode, ranked by frecency.
vim.fn.mkdir('/tmp/lusty_nfs_dir', 'p')
frec.record('/tmp/lusty_nfs_dir')
nr2.set_mode('dirs')
nr2.run()
p = pick.active_pick()
p:handle('clear')
assert(p.total >= 1, 'dirs MRU lists recorded dirs, got ' .. tostring(p.total))
assert(p.items[1].is_dir, 'dirs MRU items are dirs')
assert_eq(p.items[1].path, '/tmp/lusty_nfs_dir', 'most recent dir first')
p:handle('cancel')
nr2.set_mode('files')
print('PASS native frecency')

-- ------***------------------------------------
-- Multi-select (buffers): C-Space marks, C-d removes the whole marked set.
mk_listed('/tmp/lusty_mark_a.txt', { 'a' })
local bm2 = mk_listed('/tmp/lusty_mark_b.txt', { 'b' })
vim.cmd('buffer ' .. bm2)
bs.reset()
nbufs.run()
p = pick.active_pick()
assert(p.multi, 'buffer picker enables multi-select')
p:handle('clear')
assert(p.total >= 2, 'buffers listed, got ' .. tostring(p.total))
p.selected = 0
p:handle('mark')
p.selected = 1
p:handle('mark')
assert_eq(#p.mark_order, 2, 'two buffers marked')
p:handle('mark') -- C-Space on the same entry unmarks it
assert_eq(#p.mark_order, 1, 'C-Space toggles a mark off')
p:handle('mark')
assert_eq(#p.mark_order, 2, 're-marked')
local last = vim.api.nvim_buf_line_count(p.buf)
local prompt_line = vim.api.nvim_buf_get_lines(p.buf, last - 1, last, false)[1] or ''
assert(prompt_line:find('2 marked', 1, true), 'prompt shows the marked count: ' .. prompt_line)
local ns_id = vim.api.nvim_get_namespaces()['lusty_native_pick']
local painted = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(p.buf, ns_id, 0, -1, { details = true })) do
  if m[4] and m[4].hl_group == 'LustyNativeMark' then
    painted = true
  end
end
assert(painted, 'marked buffer carries the mark highlight')
local marked = { p.mark_order[1].item.bufnr, p.mark_order[2].item.bufnr }
p:handle('delete')
assert_eq(vim.fn.buflisted(marked[1]), 0, 'first marked buffer unloaded')
assert_eq(vim.fn.buflisted(marked[2]), 0, 'second marked buffer unloaded')
assert_eq(#p.mark_order, 0, 'marks cleared after the bulk delete')
p:handle('cancel')
print('PASS native multi-select (buffers)')

-- ------***------------------------------------
-- Multi-select (recent): Enter opens every marked file, first edit then badd.
local rm = '/tmp/lusty_nfs_marks_recent.md'
vim.fn.writefile({ 'x' }, rm)
nr2.set_mode('files')
nr2.set_recent_fn(function() return { rm, '/etc/nixos/flake.nix' } end)
nr2.run()
p = pick.active_pick()
p:handle('clear')
assert(p.multi, 'recent picker enables multi-select')
p.selected = 0
p:handle('mark')
p.selected = 1
p:handle('mark')
assert_eq(#p.mark_order, 2, 'two recent files marked')
local wanted = { p.mark_order[1].item.path, p.mark_order[2].item.path }
p:handle('enter')
assert_eq(vim.fn.bufexists(wanted[1]), 1, 'first marked file loaded: ' .. wanted[1])
assert_eq(vim.fn.bufexists(wanted[2]), 1, 'second marked file added: ' .. wanted[2])
assert_eq(vim.api.nvim_buf_get_name(0), wanted[1], 'first marked file is current')
print('PASS native multi-select (recent)')

H.finish('ALL NATIVE FLOAT SMOKE TESTS PASSED')
