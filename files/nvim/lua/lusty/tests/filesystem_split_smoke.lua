-- Filesystem picker window smoke: the picker is a plain bottom split — not a
-- float and not a frame — that spans the tabpage, follows a resize, keeps its
-- preview pane as a vertical split beside it and leaves the user's layout (and
-- nvim's autocmd/process state) exactly as it found them. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_split_smoke.lua
-- Requires the lusty binary on PATH.

local base = vim.fn.fnamemodify(arg[0], ':p:h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

local assert_eq = H.assert_eq

if not H.require_lusty('filesystem split smoke') then return end

-- Isolate the frecency journal (the client ships F records).
H.isolate_frecency('/tmp/lusty_fs_split_frec.json')

local tmp = '/tmp/lusty_fs_split_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'one' }, tmp .. '/aaa.txt')
vim.fn.writefile({ 'two' }, tmp .. '/bbb.txt')

local api = vim.api
local native = require('lusty.native')
local orig_win = api.nvim_get_current_win()
local wins_before = #api.nvim_tabpage_list_wins(0)

-- A ':split' copies the window-local options of its source: the picker must
-- clear the status column, otherwise the grid ends up shifted right.
vim.o.statuscolumn = '%3l %s'

local p = native.run(tmp)
assert(p, 'filesystem picker opens')
H.wait_until(function() return not p.loading end, 'first listing')

--- Widest display width among the picker rows (the grid pads to the window).
local function grid_width()
  local maxw = 0
  for _, line in ipairs(api.nvim_buf_get_lines(p.buf, 0, -1, false)) do
    local w = vim.fn.strdisplaywidth(line)
    if w > maxw then
      maxw = w
    end
  end
  return maxw
end

-- 1. A window in the tabpage layout, not a float: `relative` is empty and no
-- border is requested (a floating window would carry "editor" and "rounded").
local cfg = api.nvim_win_get_config(p.win)
assert_eq(cfg.relative, '', 'picker window is not floating')
assert_eq(cfg.border, nil, 'picker window has no border')
assert_eq(api.nvim_win_get_width(p.win), vim.o.columns, 'picker spans the tabpage width')
assert_eq(p:width(), vim.o.columns, 'geometry width follows the split')
assert_eq(api.nvim_buf_line_count(p.buf), p:height(), 'buffer is exactly the window height')
assert_eq(grid_width(), vim.o.columns, 'grid rows are padded to the window width')

-- 2. No frame chrome: no gutter, no cursorline, a blank statusline painted in
-- the body colour, and the window's own separator keeps the dim colour.
local wo = vim.wo[p.win]
assert_eq(wo.number, false, 'no line numbers')
assert_eq(wo.relativenumber, false, 'no relative numbers')
assert_eq(wo.signcolumn, 'no', 'no sign column')
assert_eq(wo.statuscolumn, '', 'no status column inherited from the split source')
assert_eq(wo.cursorline, false, 'no cursorline')
assert_eq(wo.statusline, ' ', 'statusline row is blank')
assert(wo.winhl:find('Normal:LustyNativeFloat', 1, true), 'body uses the panel colour')
assert(not wo.winhl:find('FloatBorder', 1, true), 'no FloatBorder group is set')

-- 3. The layout above stays on screen: the picker split the buffer window
-- instead of replacing it.
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before + 1, 'picker is an extra window')
assert(api.nvim_win_is_valid(orig_win), 'the window above still exists')

-- 4. A split follows its geometry: the grid is re-flowed to the new height on
-- the next key (the resize events themselves need a display update, which a
-- headless run never has).
api.nvim_win_set_height(p.win, 8)
p:handle('down')
assert_eq(api.nvim_buf_line_count(p.buf), 8, 'grid re-flowed to the new height')

-- 5. Preview: a vertical split of the same height beside the picker, not a
-- float; the picker gives it the columns and re-flows into the rest.
if p.caps.preview then
  p:handle('toggle_preview')
  assert(p.preview_on, 'preview toggled on')
  assert(p.preview_win and api.nvim_win_is_valid(p.preview_win), 'preview window exists')
  assert_eq(api.nvim_win_get_config(p.preview_win).relative, '', 'preview is not floating')
  assert_eq(
    api.nvim_win_get_height(p.preview_win),
    api.nvim_win_get_height(p.win),
    'preview shares the picker height'
  )
  local picker_pos = api.nvim_win_get_position(p.win)
  local pane_pos = api.nvim_win_get_position(p.preview_win)
  assert_eq(pane_pos[1], picker_pos[1], 'preview shares the picker row')
  assert_eq(
    pane_pos[2],
    picker_pos[2] + api.nvim_win_get_width(p.win) + 1,
    'preview sits to the right of the picker'
  )
  assert(api.nvim_win_get_width(p.win) < vim.o.columns, 'picker narrowed for the pane')
  assert_eq(grid_width(), api.nvim_win_get_width(p.win), 'grid re-flowed into the narrow picker')
  -- A resize event with an unchanged pane must not re-request the preview: the
  -- backend render (chafa/git/man) would otherwise run for every frame of an
  -- interactive drag.
  local rendered = 0
  local orig_request = p.request
  p.request = function(self, parts, handler)
    if parts[1] == 'V' then
      rendered = rendered + 1
    end
    return orig_request(self, parts, handler)
  end
  for _ = 1, 5 do
    p:on_win_resized()
  end
  vim.wait(300)
  p.request = orig_request
  assert_eq(rendered, 0, 'unchanged geometry sends no preview request, got ' .. rendered)
  p:handle('toggle_preview')
  assert_eq(api.nvim_win_get_width(p.win), vim.o.columns, 'picker got the columns back')
  assert_eq(grid_width(), vim.o.columns, 'grid re-flowed back to the full width')
else
  print('note: backend without preview, the preview pane assertions are skipped')
end

-- 6. Closing restores the layout the picker was opened over.
p:handle('cancel')
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before, 'layout restored after cancel')

-- 7. Navigating re-opens the picker (restart): the split height the user chose
-- must survive the restart, and the closed picker must not leave its global
-- resize autocmd behind (it fires on every later resize otherwise).
local p2 = native.run(tmp)
H.wait_until(function() return not p2.loading end, 'listing for the restart check')
api.nvim_win_set_height(p2.win, 10)
local np = p2:cycle_depth() -- restart at the same root, depth + 1
H.wait_until(function() return not np.loading end, 'listing after the restart')
assert_eq(api.nvim_win_get_height(np.win), 10, 'split height survives a restart')
local stale = 0
for _, au in ipairs(api.nvim_get_autocmds({ event = 'WinResized' })) do
  if au.group_name and au.group_name:match('^LustyPick') then
    stale = stale + 1
  end
end
assert_eq(stale, 1, 'only the live picker keeps a resize autocmd, got ' .. stale)
np:handle('cancel')
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before, 'layout restored after the restart check')

-- 8. The generic list picker (buffers/grep/recent) shares the same window.
local pick = require('lusty.native_pick')
local nbufs = require('lusty.native_buffers')
nbufs.run()
local lp = pick.active_pick()
assert(lp, 'list picker opens')
assert_eq(api.nvim_win_get_config(lp.win).relative, '', 'list picker is not floating')
assert_eq(api.nvim_win_get_width(lp.win), vim.o.columns, 'list picker spans the tabpage')
lp:handle('cancel')

-- 9. Opening and closing the picker must leave the user's window sizes alone:
-- nvim re-equalizes the layout around a split ('equalalways'), so the picker
-- replays a size snapshot taken before the split.
local function sizes()
  local t = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    t[#t + 1] = api.nvim_win_get_width(w) .. 'x' .. api.nvim_win_get_height(w)
  end
  table.sort(t)
  return table.concat(t, ' ')
end
vim.cmd('split')
api.nvim_win_set_height(0, 12)
vim.cmd('split')
api.nvim_win_set_height(0, 4)
local layout_before = sizes()
local p3 = native.run(tmp)
H.wait_until(function() return not p3.loading end, 'listing for the layout check')
p3:handle('cancel')
assert_eq(sizes(), layout_before, 'window sizes survive a picker round trip')
vim.cmd('only')

-- 10. The picker window can die outside the key handlers (':q', ':close',
-- ':only', a plugin): the backend job and the autocmds must go with it.
local p4 = native.run(tmp)
H.wait_until(function() return not p4.loading end, 'listing for the external-close check')
api.nvim_win_close(p4.win, true)
H.wait_until(function() return p4.closed end, 'picker notices the closed window')
assert_eq(vim.fn.jobwait({ p4.job }, 0)[1] ~= -1, true, 'backend job stopped with the window')
local left = {}
for _, name in ipairs(vim.fn.getcompletion('', 'augroup')) do
  if name:match('^LustyPick') then
    left[#left + 1] = name
  end
end
assert_eq(#left, 0, 'no Lusty autocmd groups survive the teardown: ' .. table.concat(left, ','))
assert_eq(#api.nvim_tabpage_list_wins(0), wins_before, 'layout restored after the external close')

H.finish('PASS filesystem split smoke')
