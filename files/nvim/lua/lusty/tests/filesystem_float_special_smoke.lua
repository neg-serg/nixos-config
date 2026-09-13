-- Filesystem float protocol smoke: names containing TAB / backslash and a
-- non-UTF8 byte must survive the serve round-trip. The backend escapes TAB/LF
-- and backslash on the wire and sends the path as raw bytes; the client
-- (`unescape` in lusty.native) restores them. Runs headless like the others:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/filesystem_float_special_smoke.lua
-- Requires the lusty binary on PATH (the test skips when it is missing, or
-- when the binary predates protocol escaping).

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP filesystem float special smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

-- Isolate the frecency journal: the client ships F records and a stale real
-- journal would reorder the empty query.
require('lusty.frecency').set_state_file('/tmp/lusty_fs_special_frec.json')
pcall(vim.fn.delete, '/tmp/lusty_fs_special_frec.json')

local tmp = '/tmp/lusty_fs_special_smoke'
vim.fn.delete(tmp, 'rf')
vim.fn.mkdir(tmp, 'p')

local names = {
  'tab\tname.txt',
  'back\\slash.txt',
  'nl\nname.txt',
}
for _, n in ipairs(names) do
  local f = assert(io.open(tmp .. '/' .. n, 'w'))
  f:write('x')
  f:close()
end
-- Raw latin-1 byte in the name: invalid UTF-8, so it can only survive as bytes.
local raw_name = 'caf' .. string.char(0xE9) .. '.txt'
local rf = assert(io.open(tmp .. '/' .. raw_name, 'w'))
rf:write('x')
rf:close()

--- Capability probe: the deployed backend may predate protocol escaping. A new
--- backend writes the TAB inside the name as the two bytes `\t`, so the R row
--- carries exactly one raw TAB (the field separator); an old one emits the raw
--- byte. Skip (do not fail) while an older binary is still deployed.
local function backend_escapes()
  local acc = ''
  local job = vim.fn.jobstart({ 'lusty', 'serve', tmp, '--depth', '1', '--skip', '' }, {
    on_stdout = function(_, data)
      acc = acc .. table.concat(data, '\n')
    end,
  })
  if job <= 0 then
    return false
  end
  vim.fn.chansend(job, 'Q\t0\t50\t\n')
  local t0 = vim.loop.hrtime()
  while not acc:match('\nE\n?$') and (vim.loop.hrtime() - t0) / 1e6 < 3000 do
    vim.wait(10)
  end
  vim.fn.jobstop(job)
  -- New backend: every R row has exactly one raw TAB (the separator) and the
  -- TAB inside the name is the two bytes `\t`. Old backend: the tab-name row
  -- carries a second raw TAB and the LF-name row is split mid-line.
  local saw_row = false
  for line in acc:gmatch('[^\n]+') do
    if line:sub(1, 2) == 'R ' then
      saw_row = true
      local tabs = 0
      for _ in line:gmatch('\t') do
        tabs = tabs + 1
      end
      if tabs > 1 then
        return false
      end
    end
  end
  return saw_row
end

if not backend_escapes() then
  print('SKIP filesystem float special smoke: backend without protocol escaping')
  vim.cmd('qa!')
  return
end

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

wait_until(function() return p.window and #p.window > 0 end, 'initial rows')

local function find_path(want)
  for _, item in ipairs(p.window) do
    if item.path == want then
      return item
    end
  end
  return nil
end

-- Escaped wire bytes are unescaped back to the real name. Display labels keep
-- control escapes visible (a raw LF breaks nvim_buf_set_lines, a raw TAB the
-- grid pitch), while paths carry the exact bytes.
local tab = find_path(tmp .. '/tab\tname.txt')
assert(tab, 'TAB name round-trips through the protocol')
assert(tab.label == 'tab\\tname.txt', 'visible TAB label: ' .. tostring(tab.label))

local back = find_path(tmp .. '/back\\slash.txt')
assert(back, 'backslash name round-trips through the protocol')
assert(back.label == 'back\\slash.txt', 'real backslash label: ' .. tostring(back.label))

local nl = find_path(tmp .. '/nl\nname.txt')
assert(nl, 'LF name round-trips through the protocol (framing is intact)')
assert(nl.label == 'nl\\nname.txt', 'visible LF label: ' .. tostring(nl.label))

-- Non-UTF8: the path keeps the raw byte; the label is the lossy display form
-- (nvim_buf_set_lines would reject invalid UTF-8).
local raw = find_path(tmp .. '/' .. raw_name)
assert(raw, 'non-UTF8 path keeps its raw bytes')
assert(raw.label == 'caf\239\191\189.txt', 'lossy label for display: ' .. tostring(raw.label))

p:handle('cancel')
print('PASS filesystem float special smoke')
vim.cmd('qa!')
