-- Theme parity: `lusty --theme-map` must resolve the same [lusty.selection] /
-- [lusty.match] values as lusty/theme.lua for one fixture file, so the two
-- readers (Rust standalone, Lua float) cannot drift. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/theme_parity_smoke.lua
-- Requires the lusty binary on PATH; skips when it predates the dump flag.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

if vim.fn.executable('lusty') ~= 1 then
  print('SKIP theme parity smoke: lusty not on PATH')
  vim.cmd('qa!')
  return
end

local help = table.concat(vim.fn.systemlist({ 'lusty', '--help' }), '\n')
if not help:find('--theme-map', 1, true) then
  print('SKIP theme parity smoke: backend without the dump flag')
  vim.cmd('qa!')
  return
end

local fixture = '/tmp/lusty_theme_parity.toml'
vim.fn.writefile({
  '[lusty.selection]',
  'bg = "#112233"',
  'fg = "#445566"',
  'bold = false',
  'underline = true',
  'reverse = false',
  '[lusty.match]',
  'fg = "#778899"',
  'underline = false',
}, fixture)
vim.env.LUSTY_THEME = fixture

local dump = {}
for _, line in ipairs(vim.fn.systemlist({ 'lusty', '--theme-map' })) do
  local k, v = line:match('^([^\t]+)\t(.*)$')
  assert(k, 'bad --theme-map line: ' .. vim.inspect(line))
  dump[k] = v
end

local theme = require('lusty.theme')
local sel = theme.selection()
local mt = theme.match()
local function check(key, got)
  assert(
    dump[key] == got,
    key .. ': rust=' .. tostring(dump[key]) .. ' lua=' .. tostring(got)
  )
end
check('selection.bg', sel.bg)
check('selection.fg', sel.fg)
check('selection.bold', tostring(sel.bold))
check('selection.underline', tostring(sel.underline))
check('selection.reverse', tostring(sel.reverse))
check('match.fg', mt.fg)
check('match.underline', tostring(mt.underline))

vim.env.LUSTY_THEME = nil
print('PASS theme parity smoke')
vim.cmd('qa!')
