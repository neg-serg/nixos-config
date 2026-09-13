-- Filesystem float preview smoke: C-r opens the preview pane to the right, the
-- backend renders the selected file (content / git diff / man / chafa) and
-- SGR colour runs become extmarks, while plain rows stay dimmed. Toggling again
-- closes it. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_preview_smoke.lua
-- Requires the lusty binary on PATH; skips when it has no preview capability.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float preview smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal (the client ships F records).
local frec = require('lusty.frecency')
frec.set_state_file('/tmp/lusty_fs_preview_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_preview_frec.json')

local tmp = '/tmp/lusty_fs_preview_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'first line', 'second line' }, tmp .. '/note.txt')
-- chafa art carries SGR; a text file with the same sequences exercises the
-- client parser without needing an image and chafa installed.
vim.fn.writefile({ '\27[38;5;9mRED\27[0m' }, tmp .. '/color.txt')

local native = require('lusty.native')
local p = native.run(tmp)
assert(p, 'filesystem picker opens')

local function wait_until(cond, what, ms)
  ms = ms or 5000
  local t0 = vim.loop.hrtime()
  while not cond() do
    if (vim.loop.hrtime() - t0) / 1e6 > ms then
      error('timeout waiting for ' .. what)
    end
    vim.wait(10)
  end
end

wait_until(function() return not p.loading end, 'first listing')

if not p.caps.preview then
  print('SKIP filesystem float preview smoke: backend without preview')
  vim.cmd('qa!')
  return
end

local function pane_lines()
  if not p.preview_buf or not vim.api.nvim_buf_is_valid(p.preview_buf) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(p.preview_buf, 0, -1, false)
end

local function fg_groups()
  local ns_id = vim.api.nvim_get_namespaces()['lusty_native_preview']
  local out = {}
  if not ns_id then
    return out
  end
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(p.preview_buf, ns_id, 0, -1, { details = true })) do
    local g = m[4] and m[4].hl_group
    if g and g:match('^LustyPreviewF') then
      out[g] = true
    end
  end
  return out
end

-- color.txt sorts first.
assert(p.window[1] and p.window[1].label == 'color.txt', 'color.txt is listed first')

p:handle('toggle_preview')
assert(p.preview_on, 'preview toggled on')
assert(p.preview_win and vim.api.nvim_win_is_valid(p.preview_win), 'preview window exists')

-- The escape bytes are consumed by the parser, so the buffer holds plain text.
wait_until(function() return pane_lines()[1] == 'RED' end, 'SGR row rendered as plain text')
-- A backend that strips SGR server-side (revision before ANSI passthrough)
-- yields no colour runs; assert the colours only when it passes them through.
local raw_first = (p.preview_lines and p.preview_lines.lines and p.preview_lines.lines[1]) or ''
if raw_first:find('\27', 1, true) then
  wait_until(function()
    return next(fg_groups()) ~= nil
  end, 'colour extmark for the red run')
  assert(
    fg_groups()['LustyPreviewFff0000'],
    'ansi-9 maps to the xterm red: ' .. vim.inspect(fg_groups())
  )
else
  print('note: backend does not pass SGR through, colour assertions skipped')
end

-- Move to the plain file: content is shown and dimmed (no colour runs).
p:handle('down')
wait_until(function()
  return pane_lines()[1] == 'first line'
end, 'plain content follows the selection')
assert(pane_lines()[2] == 'second line', 'second line rendered')
assert(next(fg_groups()) == nil, 'plain rows carry no colour runs')

p:handle('toggle_preview')
assert(not p.preview_on, 'preview toggled off')
assert(p.preview_win == nil, 'preview window closed')

p:handle('cancel')
print('PASS filesystem float preview smoke')
vim.cmd('qa!')
