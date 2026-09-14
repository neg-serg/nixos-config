-- Buffer-grep pattern translation + dircolors group creation smoke. These were
-- covered by the removed Lua-port smoke through its own UI; the pattern
-- translator and the LS_COLORS reader are still live (native_buffer_grep,
-- every picker's cell colouring).
--   nvim --clean --headless -l files/nvim/lua/lusty/tests/grep_pattern_smoke.lua

local base = vim.fn.fnamemodify(arg[0], ':h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local function assert_eq(got, want, msg)
  if got ~= want then
    error((msg or 'assert') .. ': got ' .. tostring(got) .. ' want ' .. tostring(want))
  end
end

-- Ruby-ish -> Vim magic: groups and alternation are escaped and the pattern is
-- case-insensitive (\c appended).
local gp = require('lusty.grep_pattern')
assert_eq(gp.translate_regex('a(b|c)'), 'a\\(b\\|c\\)\\c')
assert_eq(gp.translate_regex('\\d\\w\\s'), '[0-9][0-9A-Za-z_][ \t]\\c')
assert_eq(gp.translate_regex('[a-z]+'), '[a-z]\\+\\c', 'classes pass through')

-- Behaviour of the translated patterns (what the picker actually runs).
assert(vim.regex(gp.translate_regex('a+')):match_str('caaab') ~= nil, '+ quantifier')
assert(vim.regex(gp.translate_regex('colou?r')):match_str('color') ~= nil, '? quantifier')
assert(vim.regex(gp.translate_regex('a{2,3}')):match_str('aa') ~= nil, '{m,n} quantifier')
local boundary = gp.translate_regex('\\bneedle\\b')
assert(vim.regex(boundary):match_str('needle here') ~= nil, 'word boundary at a word start')
assert(vim.regex(boundary):match_str('xneedlex') == nil, 'word boundary rejects inside a word')

-- The native grep re-exports the same translator.
local ngrep = require('lusty.native_buffer_grep')
assert_eq(ngrep.translate_regex('a(b|c)'), gp.translate_regex('a(b|c)'))

-- dircolors groups are still created from LS_COLORS (every picker's cells).
vim.env.LS_COLORS = 'di=01;34:ln=01;36:ex=01;32:*.jpg=01;35:*.lua=38;5;114'
local lsc = require('lusty.ls_colors')
lsc.reset()
assert(lsc.group_for({ name = 'sub', is_dir = true }) ~= nil, 'dir gets a di group')
assert(lsc.group_for({ name = 'pic.jpg' }) ~= nil, 'jpg matches *.jpg')
assert(lsc.group_for({ name = 'beta.lua' }) ~= nil, 'lua matches *.lua')
assert(lsc.group_for({ name = 'alpha.txt' }) == nil, 'no rule for .txt')

print('PASS grep pattern smoke')
vim.cmd('qa!')
