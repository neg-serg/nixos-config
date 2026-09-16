-- Filesystem float multi-select smoke: C-Space marks files, the prompt shows
-- the count, marked cells get the LustyNativeMark highlight, and Enter with
-- marks opens them all (first via edit, the rest via badd). Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_marks_smoke.lua
-- Requires the lusty binary on PATH (skips when it is missing).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('filesystem float marks smoke') then return end

-- Keep the frecency journal out of the real state dir and deterministic (a
-- stale journal would reorder the empty query).
local frec = H.isolate_frecency('/tmp/lusty_marks_frecency.json')
frec.set_now(function() return 1700000000 end)

local tmp = '/tmp/lusty_fs_marks_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
for _, n in ipairs({ 'm1.txt', 'm2.txt', 'm3.txt' }) do
  vim.fn.writefile({ 'x' }, tmp .. '/' .. n)
end

local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')

local wait_until = H.wait_until

wait_until(function() return p.window and #p.window > 0 end, 'initial rows')
assert(p.window[1].label == 'm1.txt', 'name order first')

-- C-Space marks the cursor entry; pressing it again unmarks.
p:handle('mark')
assert(#p.mark_order == 1, 'one mark after C-Space: ' .. #p.mark_order)
assert(p.marked[p.mark_order[1]], 'mark is registered by path')

p:handle('down')
p:handle('mark')
assert(#p.mark_order == 2, 'two marks: ' .. #p.mark_order)
p:handle('mark')
assert(#p.mark_order == 1, 'C-Space toggles the mark off: ' .. #p.mark_order)

-- Mark the second file again; the prompt and the highlight reflect the marks.
p:handle('mark')
assert(#p.mark_order == 2, 'two marks before open')
assert(p:prompt_text():find('2 marked', 1, true), 'prompt shows the count')

local ns_id = vim.api.nvim_get_namespaces()['lusty_native_ls']
assert(ns_id, 'highlight namespace is registered')
local painted = false
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(p.buf, ns_id, 0, -1, { details = true })) do
  if m[4] and m[4].hl_group == 'LustyNativeMark' then
    painted = true
  end
end
assert(painted, 'marked cell carries the LustyNativeMark highlight')

-- Enter opens every marked file: the first is the current buffer, the rest are
-- added as buffers (not loaded over the first).
local wanted = {}
for _, path in ipairs(p.mark_order) do
  wanted[#wanted + 1] = path
end
p:handle('enter')
for _, path in ipairs(wanted) do
  assert(vim.fn.bufexists(path) == 1, 'buffer exists for ' .. path)
end
local current = vim.api.nvim_buf_get_name(0)
assert(current == wanted[1], 'first marked file is current: ' .. current .. ' vs ' .. wanted[1])

H.finish('PASS filesystem float marks smoke')
