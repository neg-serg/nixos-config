-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ OXY2DEV fancy diagnostics (scripts/diagnostics.lua)                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  {
    'OXY2DEV/oxy-nvim',
    lazy = true,
    cmd = { 'FancyDiagnostics' },
    config = function()
      local ok, hl = pcall(require, 'scripts.highlights')
      if ok then hl.setup() end
      local ok2, diag = pcall(require, 'scripts.diagnostics')
      if ok2 then diag.setup() end
    end,
  },
}
