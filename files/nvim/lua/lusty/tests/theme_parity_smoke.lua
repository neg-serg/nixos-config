-- Theme parity: `lusty --theme-map` must resolve the same [lusty.profile] /
-- [lusty.colors] values as lusty/theme.lua for one fixture file, so the two
-- readers (Rust standalone, Lua nvim picker) cannot drift. Runs headless:
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/theme_parity_smoke.lua
-- Requires the lusty binary on PATH; skips when it predates the dump flag.

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local H = require('lusty.tests.harness')

if not H.require_lusty('theme parity smoke') then return end

if not H.has_flag('--theme-map') then
  return H.skip('theme parity smoke', 'backend without the dump flag')
end

local fixture = '/tmp/lusty_theme_parity.toml'
-- The fixture has to satisfy the contrast floors the Rust reader enforces for
-- the three text roles (fg_current, input, footer: 4.5:1 against bg). A
-- violating theme is sanitized Rust-side by design while the Lua reader stays
-- a plain parser, so such a fixture would compare different values.
vim.fn.writefile({
  '[lusty.profile]',
  'prompt = "❯  "',
  'pointer = "▶"',
  'marker = "✓"',
  'footer_underline = false',
  '[lusty.colors]',
  'bg = "#101010"',
  'fg = "#102030"',
  'fg_current = "#ffffff"',
  'hl = "#203040"',
  'hl_current = "#ffffff"',
  'border = "#304050"',
  'separator = "#405060"',
  'info = "#506070"',
  'input = "#ffffff"',
  'prompt = "#607080"',
  'pointer = "#708090"',
  'marker = "#8090a0"',
  'footer = "#ffffff"',
  'preview_fg = "#90a0b0"',
}, fixture)
vim.env.LUSTY_THEME = fixture

local dump = {}
for _, line in ipairs(vim.fn.systemlist({ 'lusty', '--theme-map' })) do
  local k, v = line:match('^([^\t]+)\t(.*)$')
  assert(k, 'bad --theme-map line: ' .. vim.inspect(line))
  dump[k] = v
end

-- Older backends expose --theme-map but dump the old selection/match keys:
-- the profile sections landed with the fzf style, so skip until the deployed
-- binary carries them (the flake pin is bumped separately).
if not dump['colors.bg'] then
  vim.env.LUSTY_THEME = nil
  return H.skip('theme parity smoke', 'backend without the profile dump')
end

local theme = require('lusty.theme')
local profile = theme.profile()
local colors = theme.colors()
local function check(key, got)
  assert(
    dump[key] == got,
    key .. ': rust=' .. tostring(dump[key]) .. ' lua=' .. tostring(got)
  )
end
check('profile.prompt', profile.prompt)
check('profile.pointer', profile.pointer)
check('profile.marker', profile.marker)
check('profile.footer_underline', tostring(profile.footer_underline))
for _, key in ipairs({
  'bg',
  'fg',
  'fg_current',
  'hl',
  'hl_current',
  'border',
  'separator',
  'info',
  'input',
  'prompt',
  'pointer',
  'marker',
  'footer',
  'preview_fg',
}) do
  check('colors.' .. key, colors[key])
end

vim.env.LUSTY_THEME = nil
H.finish('PASS theme parity smoke')
