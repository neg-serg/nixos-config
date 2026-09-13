-- Filesystem float preview smoke: C-r opens the preview pane to the right,
-- the backend renders the selected file's content, and toggling again closes
-- it. Runs headless:
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

assert(p.window[1] and p.window[1].label == 'note.txt', 'note.txt is listed')

p:handle('toggle_preview')
assert(p.preview_on, 'preview toggled on')
assert(p.preview_win and vim.api.nvim_win_is_valid(p.preview_win), 'preview window exists')
wait_until(function()
  return p.preview_buf
    and vim.api.nvim_buf_is_valid(p.preview_buf)
    and vim.api.nvim_buf_get_lines(p.preview_buf, 0, -1, false)[1] == 'first line'
end, 'preview rendered in the pane buffer')
assert(p.preview_lines.lines[2] == 'second line', 'second line rendered')

p:handle('toggle_preview')
assert(not p.preview_on, 'preview toggled off')
assert(p.preview_win == nil, 'preview window closed')

p:handle('cancel')
print('PASS filesystem float preview smoke')
vim.cmd('qa!')
