-- LustyExplorer port: headless regression smoke test.
-- Run: nvim --clean --headless -l files/nvim/lua/lusty/tests/smoke.lua

-- Deterministic dircolors palette for the coloring assertions (do not depend
-- on whatever LS_COLORS the calling shell exports).
vim.env.LS_COLORS = 'di=01;34:ln=01;36:ex=01;32:*.jpg=01;35'

local base = vim.fn.fnamemodify(arg[0], ':p:h') .. '/../..'
package.path = base .. '/?.lua;' .. base .. '/?/init.lua;' .. package.path

local function assert_eq(got, want, msg)
  if got ~= want then
    error((msg or 'assert') .. ': got ' .. tostring(got) .. ' want ' .. tostring(want))
  end
end

local dir = '/tmp/lusty_smoke_dir'
vim.fn.mkdir(dir .. '/sub', 'p')
vim.fn.writefile({ 'gamma' }, dir .. '/sub/gamma.txt')
vim.fn.writefile({ 'x' }, dir .. '/.hidden')
vim.fn.writefile({ 'x' }, dir .. '/pic.jpg')
vim.fn.chdir(dir)

vim.cmd('edit ' .. dir .. '/alpha.txt')
vim.cmd('badd ' .. dir .. '/beta.lua')
vim.cmd('enew')
vim.api.nvim_buf_set_name(0, 'scratch_one')

local ok, err = pcall(require, 'lusty')
assert(ok, 'require lusty: ' .. tostring(err))
local fs = require('lusty.filesystem_explorer')
local be = require('lusty.buffer_explorer')
local bg = require('lusty.buffer_grep')

-- Filesystem explorer.
vim.cmd('edit ' .. dir .. '/alpha.txt')
fs.run(dir)
local e = fs.explorer()
assert(e.running, 'fs should be running')
local labels = {}
for _, m in ipairs(e.matches) do labels[#labels + 1] = m.label end
assert(vim.tbl_contains(labels, 'alpha.txt'), 'alpha.txt listed')
assert(not vim.tbl_contains(labels, '.hidden'), 'dotfiles hidden by default')
assert(not vim.tbl_contains(labels, '../'), 'parent hidden by default')

-- dircolors coloring: dirs get the di group, jpg files get *.jpg, plain
-- files without a matching rule stay uncolored.
local lsc = require('lusty.ls_colors')
local function find_entry(name)
  for _, m in ipairs(e.matches) do
    if m.label == name then return m end
  end
  return nil
end
assert(lsc.group_for(find_entry('sub/')) ~= nil, 'dir colored (di)')
assert(lsc.group_for(find_entry('pic.jpg')) ~= nil, 'jpg colored')
assert(lsc.group_for(find_entry('alpha.txt')) == nil, 'txt has no rule')
assert(lsc.group_for(find_entry('beta.lua')) ~= nil, 'lua colored via extra rules')

-- Multi-row layout + footer hint: several visible lines, hint about '.'.
assert_eq(e.row_count, 4, 'multi-row layout (4 rows)')
local cur_buf = vim.api.nvim_get_current_buf()
local nlines = vim.api.nvim_buf_line_count(cur_buf)
assert(nlines >= 5, 'buffer shows several lines')
local footer = vim.api.nvim_buf_get_lines(cur_buf, nlines - 1, nlines, false)[1] or ''
assert(footer:find('скрытые', 1, true) ~= nil, 'hint mentions hidden files')
e:cancel()

-- Typing '.' reveals dotfiles (including the parent '..').
fs.run(dir)
e = fs.explorer()
e:key_pressed(46) -- '.'
local dot_labels = {}
for _, m in ipairs(e.matches) do dot_labels[#dot_labels + 1] = m.label end
assert(vim.tbl_contains(dot_labels, '.hidden'), '.hidden appears after dot')
assert(vim.tbl_contains(dot_labels, '../'), '.. appears after dot')
e:cancel()

-- Filtering with letters.
fs.run(dir)
e = fs.explorer()
for _, ch in ipairs({ 'b', 'e', 't', 'a' }) do e:key_pressed(string.byte(ch)) end
assert_eq(#e.matches, 1, 'one match')
assert_eq(e.matches[1].label, 'beta.lua', 'match beta.lua')
e:cancel()

fs.run(dir)
e = fs.explorer()
local sel = nil
for i, m in ipairs(e.matches) do if m.label == 'sub/' then sel = i - 1 end end
assert(sel ~= nil, 'sub/ listed')
e.selected = sel
e:key_pressed(13) -- Enter recurses into the dir
local sub_labels = {}
for _, m in ipairs(e.matches) do sub_labels[#sub_labels + 1] = m.label end
assert(vim.tbl_contains(sub_labels, 'gamma.txt'), 'entered sub/ via Enter')
e:key_pressed(23) -- C-w up one dir
local root_labels = {}
for _, m in ipairs(e.matches) do root_labels[#root_labels + 1] = m.label end
assert(vim.tbl_contains(root_labels, 'alpha.txt'), 'C-w back to parent')
e:cancel()
print('PASS filesystem explorer')

-- Buffer explorer: MRU order, navigation, C-d unload.
vim.cmd('edit ' .. dir .. '/alpha.txt')
be.run()
local be_e = be.explorer()
local order = {}
for _, m in ipairs(be_e.matches) do order[#order + 1] = m.short_name end
assert(order[#order] == 'alpha.txt', 'current buffer last')
be_e:key_pressed(14)
assert_eq(be_e.selected, 1, 'C-n moves to 1')
be_e:key_pressed(16)
assert_eq(be_e.selected, 0, 'C-p back to 0')
local victim = be_e.matches[1].short_name
be_e:key_pressed(4) -- C-d unload
assert(be_e.running, 'reopened after C-d')
for _, m in ipairs(be_e.matches) do assert(m.short_name ~= victim, 'victim removed') end
be_e:cancel()
print('PASS buffer explorer')

-- Buffer grep: hits, marks, word boundary, empty-query reset.
vim.cmd('edit ' .. dir .. '/alpha.txt')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'needle here', 'xneedlex', 'needle again' })
vim.cmd('badd ' .. dir .. '/beta.lua')
vim.api.nvim_buf_set_lines(vim.fn.bufnr(dir .. '/beta.lua'), 0, -1, false, { 'needle two' })
bg.run()
local bg_e = bg.explorer()
bg_e.prompt:set('\\bneedle\\b')
bg_e:refresh('full')
assert_eq(#bg_e.matches, 3, 'three word-boundary hits (alpha x2 + beta x1)')
for _, m in ipairs(bg_e.matches) do assert_eq(#(m.marks or {}), 4, 'marks') end
bg_e.prompt:set('needle')
bg_e:refresh('full')
assert_eq(#bg_e.matches, 4, 'four plain hits (incl. xneedlex)')
bg_e.prompt:clear()
bg_e:refresh('full')
assert(#bg_e.matches >= 2, 'empty query lists buffers')
bg_e:cancel()
print('PASS buffer grep')

print('ALL LUSTY SMOKE TESTS PASSED')

