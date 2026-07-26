return {
  'andymass/vim-matchup',
  event = { 'BufReadPost', 'BufNewFile' },
  init = function()
    vim.g.matchup_matchparen_offscreen = { method = 'popup' }
    vim.g.matchup_enabled_by_default = false
    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'rust', 'lua', 'python', 'c', 'cpp', 'vim', 'javascript', 'typescript' },
      callback = function()
        vim.b.matchup_matchparen_enabled = true
      end,
    })
  end,
}
