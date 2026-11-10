-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ justinmk/guh.nvim                                                            │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- GitHub in Neovim through the `gh` CLI: :Guh opens repo status (commits/PRs/issues),
-- PR review with comments as diagnostics and the latest CI logs. No setup needed.
-- Requires Neovim 0.13+ (vim.async): on the pinned 0.12.6 nvim the command raises
-- "attempt to index local 'async' (a nil value)" until neovim-unwrapped bumps.
return {
    'justinmk/guh.nvim',
    cmd = { 'Guh' },
}
