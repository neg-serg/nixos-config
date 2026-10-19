-- One-line mode smoke: g:LustyExplorerOneLine (or LUSTY_ONE_LINE) turns the
-- pickers into a single row where the prompt and the selected entry share the
-- line — no grid. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/one_line_smoke.lua
-- Requires the lusty binary on PATH.

local base = vim.fn.fnamemodify(arg[0], ':p:h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

local assert_eq = H.assert_eq

if not H.require_lusty('one line smoke') then return end

H.isolate_frecency('/tmp/lusty_one_line_frec.json')

local tmp = '/tmp/lusty_one_line_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'one' }, tmp .. '/aaa.txt')
vim.fn.writefile({ 'two' }, tmp .. '/bbb.txt')
vim.fn.writefile({ 'three' }, tmp .. '/bbz.txt')

local api = vim.api
local native = require('lusty.native')

--- The single row of a one-line picker ('' when the buffer is empty).
local function row(p)
  return api.nvim_buf_get_lines(p.buf, 0, -1, false)[1] or ''
end

local wins_before = #api.nvim_tabpage_list_wins(0)

-- 1. Off by default: the split keeps its normal height.
local plain = native.run(tmp)
H.wait_until(function() return not plain.loading end, 'listing without the mode')
assert_eq(api.nvim_win_get_height(plain.win), 6, 'default picker is not one line')
plain:handle('cancel')
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before, 'default picker closes cleanly')

-- 2. One row: prompt and the selected entry on the same line.
vim.g.LustyExplorerOneLine = 1
local p = native.run(tmp)
H.wait_until(function() return not p.loading end, 'listing in one-line mode')
vim.wait(200) -- the draw is scheduled after the listing arrives

assert_eq(api.nvim_win_get_height(p.win), 1, 'one-line picker is a single row')
assert_eq(api.nvim_buf_line_count(p.buf), 1, 'one-line picker owns a single buffer line')
local line = row(p)
assert(line:find(tmp, 1, true), 'the row carries the prompt path: ' .. line)
assert(line:find('aaa.txt', 1, true), 'the row carries the selected entry: ' .. line)
assert_eq(vim.fn.strdisplaywidth(line), api.nvim_win_get_width(p.win), 'the row is padded to the window')
local sel_painted = false
for _, m in ipairs(
  api.nvim_buf_get_extmarks(p.buf, api.nvim_get_namespaces()['lusty_native_ls'], 0, -1, { details = true })
) do
  if m[4] and m[4].hl_group == 'LustyNativeSel' then
    sel_painted = true
  end
end
assert(sel_painted, 'the selected entry carries the selection bar')

-- 3. The row follows typing and the selection: no grid, no scrolling.
p:handle('b')
H.wait_until(function()
  local l = row(p)
  return l:find('bbb.txt', 1, true) ~= nil
end, 'typing narrows the row to bbb.txt')
assert(row(p):find('b [2]', 1, true), 'the row shows the query and the new count: ' .. row(p))
p:handle('down')
H.wait_until(function() return row(p):find('bbz.txt', 1, true) ~= nil end, 'selection moves inline')
p:handle('up')
H.wait_until(function() return row(p):find('bbb.txt', 1, true) ~= nil end, 'selection moves back inline')

-- 4. The mode owns exactly one row: a resize is snapped back on the next key.
api.nvim_win_set_height(p.win, 9)
p:handle('down')
assert_eq(api.nvim_win_get_height(p.win), 1, 'height forced back to a single row')
assert_eq(api.nvim_buf_line_count(p.buf), 1, 'buffer stays a single line')

-- 5. The preview pane makes no sense in one row and is refused.
if p.caps.preview then
  p:handle('toggle_preview')
  assert(not p.preview_on, 'preview refused in one-line mode')
  assert_eq(#api.nvim_tabpage_list_wins(0), wins_before + 1, 'no extra window opened')
end

-- 6. Enter still opens the selection and the layout comes back.
p:handle('clear')
H.wait_until(function() return row(p):find('aaa.txt', 1, true) ~= nil end, 'listing back to the full set')
p.selected = 0
p:handle('enter')
H.wait_until(function() return api.nvim_buf_get_name(0):find('aaa.txt', 1, true) ~= nil end, 'file opened')
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before, 'layout restored after opening a file')

-- 7. The env variable selects the same mode.
vim.g.LustyExplorerOneLine = nil
vim.env.LUSTY_ONE_LINE = '1'
local q = native.run(tmp)
H.wait_until(function() return not q.loading end, 'listing via LUSTY_ONE_LINE')
vim.wait(200)
assert_eq(api.nvim_win_get_height(q.win), 1, 'LUSTY_ONE_LINE turns the mode on')
q:handle('cancel')
vim.env.LUSTY_ONE_LINE = nil

-- 8. The list pickers (buffers/grep/recent) share the mode.
local function mk_listed(name)
  local b = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(b, name)
  api.nvim_buf_set_lines(b, 0, -1, false, { 'x' })
  return b
end
mk_listed('/tmp/lusty_one_line_a.txt')
local second = mk_listed('/tmp/lusty_one_line_b.txt')
vim.cmd('buffer ' .. second)
vim.g.LustyExplorerOneLine = 1
require('lusty.buffer_stack').reset()
local pick = require('lusty.native_pick')
require('lusty.native_buffers').run()
local lp = pick.active_pick()
assert(lp, 'buffers picker opens in one-line mode')
assert_eq(api.nvim_win_get_height(lp.win), 1, 'list picker is a single row')
assert_eq(api.nvim_buf_line_count(lp.buf), 1, 'list picker owns a single buffer line')
local list_line = api.nvim_buf_get_lines(lp.buf, 0, -1, false)[1] or ''
assert(list_line:find('Buffers', 1, true), 'the row carries the title: ' .. list_line)
assert(list_line:find('lusty_one_line_', 1, true), 'the row carries the selected buffer: ' .. list_line)
lp:handle('cancel')
vim.g.LustyExplorerOneLine = nil

H.finish('PASS one line smoke')
