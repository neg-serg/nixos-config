-- ── Command-line abbreviations ───────────────────────────────────────
local function abbrev(lhs, rhs)
  vim.cmd.cnoreabbrev(lhs .. ' ' .. rhs)
end

-- Typo corrections
abbrev('W!', 'w!')
abbrev('W', 'w')
abbrev('Bd', 'bd')
abbrev('Cp', 'cp')
abbrev('E', 'e')
abbrev('Sp', 'sp')
abbrev('VS', 'vs')
abbrev('Q', 'q')
abbrev('Q!', 'q!')
abbrev('Qa', 'qa')
abbrev('QA', 'qa')
abbrev('QA!', 'qa!')
abbrev('Wq', 'wq')
abbrev('WQ', 'wq')
abbrev('wQ', 'wq')

-- Git shortcuts (!git / diffview / snacks pickers). fzf-lua is not installed:
-- these used to expand to `FzfLua ...`, which no longer exists.
abbrev('gb', 'lua Snacks.picker.git_branches()')
abbrev('gc', '!git commit -v')
abbrev('gca', '!git commit --amend -v')
abbrev('gcc', '!git checkout ')
abbrev('gd', 'DiffviewOpen')
abbrev('gl', 'lua Snacks.picker.git_log_file()') -- commits touching the current file
abbrev('gp', '!git push')
abbrev('gs', 'lua Snacks.picker.git_status()')

-- Misc: bare picker list (the old `FzfLua` with no source)
abbrev('T', 'lua Snacks.picker()')

-- ── Smart CR: expand abbreviations on keyword-only cmdlines ─────────
vim.keymap.set('c', '<CR>', function()
  local cmdline = vim.fn.getcmdline()
  if cmdline:match('^%w+$') then
    return vim.api.nvim_replace_termcodes('<C-]><CR>', true, false, true)
  end
  return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
end, { expr = true })
