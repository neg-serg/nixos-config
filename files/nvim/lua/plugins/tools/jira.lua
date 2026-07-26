-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ letieu/jira.nvim                                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'letieu/jira.nvim',
  cmd = { 'JiraBrowse', 'JiraSprint', 'JiraBoard', 'JiraSearch' },
  keys = {
    { '<leader>jb', '<Cmd>JiraBrowse<CR>', desc = 'Jira: browse current issue' },
    { '<leader>js', '<Cmd>JiraSprint<CR>', desc = 'Jira: sprint tasks' },
    { '<leader>jf', '<Cmd>JiraSearch<CR>', desc = 'Jira: search issues' },
  },
  opts = {},
}
