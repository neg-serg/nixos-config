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

--- Text currently painted with the selection bar ('' when nothing is).
local function bar_text(p)
  for _, m in ipairs(
    api.nvim_buf_get_extmarks(p.buf, api.nvim_get_namespaces()['lusty_native_ls'], 0, -1, { details = true })
  ) do
    if m[4] and m[4].hl_group == 'LustyNativeSel' then
      return row(p):sub(m[3] + 1, m[4].end_col)
    end
  end
  return ''
end

local wins_before = #api.nvim_tabpage_list_wins(0)

-- 1. Off by default: the split keeps its normal height.
local plain = native.run(tmp)
H.wait_until(function() return not plain.loading end, 'listing without the mode')
assert_eq(api.nvim_win_get_height(plain.win), 16, 'default picker is not one line')
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
assert(line:find('❯', 1, true), 'the row carries the fzf prompt glyph: ' .. line)
assert(line:find('aaa.txt', 1, true), 'the row carries the selected entry: ' .. line)
-- One row must still show the variants: the entries after the cursor follow it.
assert(line:find('bbb.txt', 1, true), 'the row shows the next entry: ' .. line)
assert(line:find('bbz.txt', 1, true), 'the row shows the entry after that: ' .. line)
assert_eq(vim.fn.strdisplaywidth(line), api.nvim_win_get_width(p.win), 'the row is padded to the window')
local bars = {}
for _, m in ipairs(
  api.nvim_buf_get_extmarks(p.buf, api.nvim_get_namespaces()['lusty_native_ls'], 0, -1, { details = true })
) do
  if m[4] and m[4].hl_group == 'LustyNativeSel' then
    bars[#bars + 1] = m
  end
end
assert_eq(#bars, 1, 'exactly one entry carries the selection bar')
assert_eq(
  line:sub(bars[1][3] + 1, bars[1][4].end_col),
  'aaa.txt',
  'the bar covers the selected entry and nothing else'
)

-- 3. The row follows typing and the selection: no grid, no scrolling. The
-- strip keeps showing the following entries, so the wait hangs off the match
-- counter and the selection bar rather than off a label appearing.
p:handle('b')
H.wait_until(function()
  local l = row(p)
  return l:find('aaa.txt', 1, true) == nil and l:find('bbb.txt', 1, true) ~= nil
end, 'typing narrows the row to the matches')
local narrowed = row(p)
assert(narrowed:find('bbz.txt', 1, true), 'both matches are visible: ' .. narrowed)
assert(not narrowed:find('aaa.txt', 1, true), 'the filtered-out entry is gone: ' .. narrowed)
p:handle('down')
H.wait_until(function() return bar_text(p) == 'bbz.txt' end, 'selection moves inline')
p:handle('up')
H.wait_until(function() return bar_text(p) == 'bbb.txt' end, 'selection moves back inline')

-- 4. The mode owns exactly one row: a resize is snapped back on the next key.
api.nvim_win_set_height(p.win, 9)
p:handle('down')
assert_eq(api.nvim_win_get_height(p.win), 1, 'height forced back to a single row')
assert_eq(api.nvim_buf_line_count(p.buf), 1, 'buffer stays a single line')

-- 4b. C-x switches to the grid and back, keeping the query and the selection.
local mapped = false
for _, m in ipairs(api.nvim_buf_get_keymap(p.buf, 'n')) do
  if m.lhs and m.lhs:lower() == '<c-x>' then
    mapped = true
  end
end
assert(mapped, 'the C-x toggle is mapped inside the picker')
p:handle('toggle_one_line')
H.wait_until(function() return api.nvim_win_get_height(p.win) > 1 end, 'grid after the toggle')
local grid_h = api.nvim_win_get_height(p.win)
H.wait_until(function() return api.nvim_buf_line_count(p.buf) == grid_h end, 'grid drawn')
local prompt_row = api.nvim_buf_get_lines(p.buf, 0, 1, false)[1] or ''
assert(prompt_row:find('b', 1, true), 'query survives the toggle: ' .. prompt_row)
local info_row = api.nvim_buf_get_lines(p.buf, 1, 2, false)[1] or ''
assert(info_row:find('2/', 1, true), 'the filtered count survives the toggle: ' .. info_row)
p:handle('toggle_one_line')
H.wait_until(function() return api.nvim_win_get_height(p.win) == 1 end, 'one row again')
H.wait_until(function() return row(p):find('bbz.txt', 1, true) ~= nil end, 'selection survives the toggle')

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
assert(list_line:find('❯', 1, true), 'the row carries the prompt glyph: ' .. list_line)
assert(list_line:find('lusty_one_line_', 1, true), 'the row carries the selected buffer: ' .. list_line)
lp:handle('cancel')
vim.g.LustyExplorerOneLine = nil

H.finish('PASS one line smoke')
