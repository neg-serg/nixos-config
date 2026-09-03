-- LustyExplorer port: headless regression smoke test.
-- Run: nvim --clean --headless -l files/nvim/lua/lusty/tests/smoke.lua

-- Deterministic dircolors palette for the coloring assertions (do not depend
-- on whatever LS_COLORS the calling shell exports).
vim.env.LS_COLORS = 'di=01;34:ln=01;36:ex=01;32:*.jpg=01;35:*.lua=38;5;114'
-- Classic single-directory listing for the tests below; the dedicated
-- depth-search test enables g:LustyExplorerSearchDepth = 2 itself.
vim.g.LustyExplorerSearchDepth = 1

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
vim.fn.mkdir(dir .. '/.hid', 'p')
vim.fn.writefile({ 'inside' }, dir .. '/.hid/marker.txt')
vim.fn.mkdir(dir .. '/sub/deep', 'p')
vim.fn.writefile({ 'z' }, dir .. '/sub/deep/foo.txt')
vim.fn.mkdir(dir .. '/pic', 'p')
vim.fn.writefile({ 'p' }, dir .. '/pic/pic_marker.txt')
vim.fn.mkdir(dir .. '/tmp', 'p')
vim.fn.writefile({ 't' }, dir .. '/tmp/tmp_marker.txt')
vim.fn.writefile({ 'x' }, dir .. '/pic.jpg')
vim.fn.chdir(dir)

vim.cmd('edit ' .. dir .. '/alpha.txt')
vim.cmd('badd ' .. dir .. '/beta.lua')
vim.cmd('enew')
vim.api.nvim_buf_set_name(0, 'scratch_one')

vim.g.mapleader = ',' -- real config sets this in init.lua before plugins
vim.o.timeoutlen = 0 -- ,l is a prefix of ,lf/,lr/..., so fire it immediately in tests
local ok, err = pcall(require, 'lusty')
assert(ok, 'require lusty: ' .. tostring(err))

local fs = require('lusty.filesystem_explorer')
local be = require('lusty.buffer_explorer')
local bg = require('lusty.buffer_grep')

-- ,l (leader+l) = LustyFilesystemExplorerFromHere: opens at the current
-- file's directory.  ,lf (from cwd) and ,lr still work as before.
vim.cmd('edit ' .. dir .. '/alpha.txt')
vim.api.nvim_feedkeys(',l', 'x!', false)
vim.wait(20)
local fe = fs.explorer()
assert(fe.running, ',l opens the from-here explorer')
assert(fe.prompt:value() == dir .. '/', 'from-here prompt is the file dir')
fe:cancel()

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
assert(lsc.group_for(find_entry('beta.lua')) ~= nil, 'lua colored from inherited LS_COLORS')

-- The colors must actually be painted as buffer highlights (regression:
-- nvim_buf_add_highlight takes no end_row; a bad call silently dropped all
-- extmarks and the listing looked monochrome).
local marks_buf = vim.api.nvim_get_current_buf()
local lusty_ns = vim.api.nvim_get_namespaces()['lusty_explorer']
local marks = vim.api.nvim_buf_get_extmarks(marks_buf, lusty_ns, 0, -1, { details = true })
local painted = 0
local prompt_hl = 0
for _, m in ipairs(marks) do
  local g = (m[4] or {}).hl_group
  if g and g:find('^LustyLs') then
    painted = painted + 1
  elseif g == 'LustyPrompt' then
    prompt_hl = prompt_hl + 1
  end
end
assert(painted >= 2, 'dircolors highlights painted on cells')

-- Prompt drawing: no footer hint anymore; an empty query renders exactly
-- '>> ' and the LustyPrompt highlight covers its prefix.
-- Root listing now has 6 visible entries (alpha/beta/pic.jpg + dirs).
assert_eq(e.row_count, 6, 'multi-row layout (6 rows)')
local cur_buf = vim.api.nvim_get_current_buf()
local nlines = vim.api.nvim_buf_line_count(cur_buf)
assert(nlines >= 5, 'buffer shows several lines')
local footer = vim.api.nvim_buf_get_lines(cur_buf, nlines - 1, nlines, false)[1] or ''
-- FS prompt shows the path being browsed (like the original LustyExplorer).
assert_eq(footer, '>> ' .. dir .. '/', 'prompt line shows >> + path')
assert(footer:find('скрытые', 1, true) == nil, 'no hint text in the prompt')
assert(prompt_hl >= 1, 'LustyPrompt painted on the footer')
e:cancel()

-- Home directory: the prompt abbreviates to '~' and paints tilde/separators/
-- path with the neg.omp.json colours (like the shell prompt).
local hdir2 = os.getenv('HOME') .. '/lusty_home_test'
vim.fn.mkdir(hdir2, 'p')
vim.cmd('edit! ' .. hdir2 .. '/a.txt')
fs.run(hdir2)
local he = fs.explorer()
local hbuf = vim.api.nvim_get_current_buf()
local hn = vim.api.nvim_buf_line_count(hbuf)
local hfoot = vim.api.nvim_buf_get_lines(hbuf, hn - 1, hn, false)[1] or ''
assert(hfoot:find('^>> ~/', 1) ~= nil, 'home abbreviated to ~ in prompt')
local hcounts = { Tilde = 0, Sep = 0, Path = 0 }
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(hbuf, lusty_ns, 0, -1, { details = true })) do
  local g = (m[4] or {}).hl_group
  if g == 'LustyPromptTilde' then hcounts.Tilde = hcounts.Tilde + 1 end
  if g == 'LustyPromptSep' then hcounts.Sep = hcounts.Sep + 1 end
  if g == 'LustyPromptPath' then hcounts.Path = hcounts.Path + 1 end
end
assert(hcounts.Tilde >= 1 and hcounts.Sep >= 1 and hcounts.Path >= 1, 'prompt path segments painted')
he:cancel()
vim.fn.system({ 'rm', '-rf', hdir2 })

-- Typing '.' reveals dotfiles (including the parent '..').
fs.run(dir)
e = fs.explorer()
e:key_pressed(46) -- '.'
local dot_labels = {}
for _, m in ipairs(e.matches) do dot_labels[#dot_labels + 1] = m.label end
assert(vim.tbl_contains(dot_labels, '.hidden'), '.hidden appears after dot')
assert(vim.tbl_contains(dot_labels, '../'), '.. appears after dot')
e:cancel()

-- RU layout (йцукен): the physical '.' key sends 'ю', 'b' sends 'и';
-- dual mappings must feed the EN query characters.
fs.run(dir)
e = fs.explorer()
vim.api.nvim_feedkeys('ю', 'x!', false)
vim.wait(30)
local ru_dot_labels = {}
for _, m in ipairs(e.matches) do ru_dot_labels[#ru_dot_labels + 1] = m.label end
assert(vim.tbl_contains(ru_dot_labels, '.hidden'), 'RU dot key reveals hidden files')
assert(vim.tbl_contains(ru_dot_labels, '.hid/'), 'RU dot key reveals hidden dirs')
assert(vim.tbl_contains(ru_dot_labels, '../'), 'RU dot key shows parent dir')
-- Hidden directories are navigable: Enter on '.hid/' lists its content.
local hid_idx = nil
for i, m in ipairs(e.matches) do
  if m.label == '.hid/' then hid_idx = i - 1 end
end
e.selected = hid_idx
e:key_pressed(13)
local hid_labels = {}
for _, m in ipairs(e.matches) do hid_labels[#hid_labels + 1] = m.label end
assert(vim.tbl_contains(hid_labels, 'marker.txt'), 'entered hidden dir via Enter')
e:cancel()

-- Depth search: with g:LustyExplorerSearchDepth = 2 nested files are listed
-- with their relative path and can be found by typing.
vim.g.LustyExplorerSearchDepth = 2
fs.run(dir)
e = fs.explorer()
local deep_labels = {}
for _, m in ipairs(e.matches) do deep_labels[#deep_labels + 1] = m.label end
assert(vim.tbl_contains(deep_labels, 'sub/gamma.txt'), 'depth 2 lists nested file')
assert(vim.tbl_contains(deep_labels, 'sub/deep/'), 'depth 2 lists level-2 dir')
-- foo.txt lives at level 3 (sub/deep/foo.txt) and must NOT be listed at depth 2.
assert(not vim.tbl_contains(deep_labels, 'sub/deep/foo.txt'), 'depth 2 excludes level-3 file')
for _, ch in ipairs({ 'g', 'a', 'm' }) do e:key_pressed(string.byte(ch)) end
local gam_hits = {}
for _, m in ipairs(e.matches) do gam_hits[#gam_hits + 1] = m.label end
assert(vim.tbl_contains(gam_hits, 'sub/gamma.txt'), 'fuzzy find hits nested file')

-- Skip dirs (default 'pic,tmp'): entries stay visible but are not walked.
assert(vim.tbl_contains(deep_labels, 'pic/'), 'skipped dir entry still visible')
assert(not vim.tbl_contains(deep_labels, 'pic/pic_marker.txt'), 'default skip pic')
assert(not vim.tbl_contains(deep_labels, 'tmp/tmp_marker.txt'), 'default skip tmp')
e:cancel()
-- Re-enabling walking into them.
vim.g.LustyExplorerSkipDirs = ''
fs.run(dir)
e = fs.explorer()
local skip_off_labels = {}
for _, m in ipairs(e.matches) do skip_off_labels[#skip_off_labels + 1] = m.label end
assert(vim.tbl_contains(skip_off_labels, 'pic/pic_marker.txt'), 'skip off walks pic')
assert(vim.tbl_contains(skip_off_labels, 'tmp/tmp_marker.txt'), 'skip off walks tmp')
e:cancel()
vim.g.LustyExplorerSkipDirs = nil
vim.g.LustyExplorerSearchDepth = 1

-- Fuzzy engine fallback: g:LustyExplorerFuzzyEngine = 'mercury' restores the
-- original scorer and still filters correctly.
vim.g.LustyExplorerFuzzyEngine = 'mercury'
fs.run(dir)
e = fs.explorer()
for _, ch in ipairs({ 'b', 'e', 't', 'a' }) do e:key_pressed(string.byte(ch)) end
assert_eq(#e.matches, 1, 'mercury engine one match')
assert_eq(e.matches[1].label, 'beta.lua', 'mercury engine match beta.lua')
e:cancel()
vim.g.LustyExplorerFuzzyEngine = nil

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

-- Cancel via real <C-c> mapping: window closes, caller buffer stays.
local big = '/tmp/lusty_big_dir'
vim.fn.mkdir(big, 'p')
for i = 1, 20 do
  vim.fn.writefile({ tostring(i) }, big .. '/file' .. string.format('%02d', i) .. '.rs')
end
vim.fn.chdir(big)
vim.cmd('edit ' .. big .. '/file01.rs')
fs.run(big)
local big_e = fs.explorer()
local float_budget = math.max(1, (math.max(6, math.floor(vim.o.lines * 0.8))) - 2)
local expected_rows = math.min(20, math.max(6, math.floor(float_budget * 0.6)))
assert_eq(big_e.row_count, expected_rows, 'tall layout uses ~60% of float')
assert(vim.api.nvim_win_get_height(0) >= expected_rows, 'window height follows rows')
local cfg = vim.api.nvim_win_get_config(0)
assert_eq(cfg.relative, 'editor', 'explorer is a floating window')
assert(cfg.width > 40, 'float has a comfortable width')
big_e:cancel()

vim.cmd('edit ' .. dir .. '/alpha.txt')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'dirty caller' }) -- modified, hidden off
local cc = vim.api.nvim_replace_termcodes('<C-c>', true, false, true)
local wins_before = #vim.api.nvim_list_wins()
local buf_before = vim.api.nvim_get_current_buf()
fs.run(dir)
vim.api.nvim_feedkeys(cc, 'x!', false)
vim.wait(30)
assert(not big_e.running, 'C-c cancels (fs singleton)')
assert_eq(#vim.api.nvim_list_wins(), wins_before, 'window count restored after C-c')
assert_eq(vim.api.nvim_get_current_buf(), buf_before, 'caller buffer intact after C-c')
assert_eq(vim.v.errmsg, '', 'no errors after C-c')
print('PASS C-c cancel + tall layout')

-- Options: float size ratios and disabling the dircolors coloring.
vim.g.LustyExplorerWidthRatio = 0.5
vim.g.LustyExplorerMaxHeightRatio = 0.5
vim.g.LustyExplorerShowColors = 0
vim.cmd('edit! ' .. dir .. '/alpha.txt')
fs.run(dir)
local opt_e = fs.explorer()
assert(opt_e.running, 'explorer opens with custom ratios')
local opt_cfg = vim.api.nvim_win_get_config(0)
assert(opt_cfg.width < 70, 'width ratio option applied (narrow float)')
local opt_marks = vim.api.nvim_buf_get_extmarks(
  vim.api.nvim_get_current_buf(), lusty_ns, 0, -1, { details = true })
local ls_marks = 0
for _, m in ipairs(opt_marks) do
  local g = (m[4] or {}).hl_group
  if g and g:find('^LustyLs') then ls_marks = ls_marks + 1 end
end
assert_eq(ls_marks, 0, 'LustyExplorerShowColors=0 disables cell colors')
opt_e:cancel()
vim.g.LustyExplorerWidthRatio = nil
vim.g.LustyExplorerMaxHeightRatio = nil
vim.g.LustyExplorerShowColors = nil
print('PASS option knobs')

-- Gravity: g:LustyExplorerGravity = top | center | bottom anchors the float;
-- the DEFAULT is bottom (like the original Lusty table).
vim.cmd('edit! ' .. dir .. '/alpha.txt')
local grav_rows = {}
for _, g in ipairs({ 'top', 'center', 'bottom' }) do
  vim.g.LustyExplorerGravity = g
  fs.run(big)
  grav_rows[g] = vim.api.nvim_win_get_config(0).row
  fs.explorer():cancel()
  vim.wait(15)
end
vim.g.LustyExplorerGravity = nil
assert(grav_rows.top < grav_rows.center, 'gravity top anchors above center')
assert(grav_rows.center < grav_rows.bottom, 'gravity bottom anchors below center')
-- Default (option unset) must equal the explicit 'bottom' anchor.
fs.run(big)
local def_row = vim.api.nvim_win_get_config(0).row
fs.explorer():cancel()
assert_eq(def_row, grav_rows.bottom, 'default gravity is bottom')
print('PASS gravity')

print('ALL LUSTY SMOKE TESTS PASSED')

