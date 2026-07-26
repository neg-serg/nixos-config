-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ dstein64/vim-startuptime                                                     │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'dstein64/vim-startuptime', -- startup time measurement
  enabled = function() return vim.env.NVIM_PROFILE == '1' end,
  cmd = 'StartupTime',
}
