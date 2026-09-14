-- Rust<->Lua table parity: `lusty --ru-map` / `lusty --icon-map` must match
-- lusty/ru2en.lua and lusty/icons.lua, so the standalone TUI and the nvim
-- floats cannot drift apart. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/tables_parity_smoke.lua
-- Requires the lusty binary on PATH; skips when it predates the dump flags.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP tables parity smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

local help = table.concat(vim.fn.systemlist({ 'lusty', '--help' }), '\n')
if not help:find('--ru-map', 1, true) then
  print('SKIP tables parity smoke: backend without the dump flags')
  vim.cmd('qa!')
  return
end

local function dump(flag)
  local out = vim.fn.systemlist({ 'lusty', flag })
  assert(vim.v.shell_error == 0, flag .. ' failed: ' .. vim.inspect(out))
  return out
end

-- RU (йцукен) key table.
local ru = require('lusty.ru2en')
local got = {}
for _, line in ipairs(dump('--ru-map')) do
  local k, v = line:match('^([^\t]+)\t([^\t]+)$')
  assert(k, 'bad --ru-map line: ' .. vim.inspect(line))
  got[k] = v
end
assert(vim.deep_equal(got, ru), 'RU table drifted: ' .. vim.inspect(got) .. ' vs ' .. vim.inspect(ru))
local n = 0
for _ in pairs(ru) do
  n = n + 1
end
assert(n == 32, 'RU table size: ' .. n)

-- Icon table.
local icons = require('lusty.icons')
local ig = { ext = {} }
for _, line in ipairs(dump('--icon-map')) do
  local kind, rest = line:match('^(%a+)\t(.*)$')
  assert(kind, 'bad --icon-map line: ' .. vim.inspect(line))
  if kind == 'ext' then
    local suffix, glyph = rest:match('^(.-)\t(.*)$')
    assert(suffix, 'bad --icon-map ext line: ' .. vim.inspect(line))
    ig.ext[#ig.ext + 1] = { suffix, glyph }
  else
    ig[kind] = rest
  end
end
assert(ig.dir == icons.dir, 'dir icon: ' .. vim.inspect(ig.dir) .. ' vs ' .. vim.inspect(icons.dir))
assert(ig.link == icons.link, 'link icon drifted')
assert(ig.file == icons.file, 'file icon drifted')
assert(#ig.ext == #icons.ext, 'ext icon count: ' .. #ig.ext .. ' vs ' .. #icons.ext)
for i, pair in ipairs(icons.ext) do
  assert(
    ig.ext[i][1] == pair[1] and ig.ext[i][2] == pair[2],
    'ext icon ' .. i .. ' drifted: ' .. vim.inspect(ig.ext[i]) .. ' vs ' .. vim.inspect(pair)
  )
end

print('PASS tables parity smoke')
vim.cmd('qa!')
