-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ OXY2DEV fancy diagnostics (scripts/diagnostics.lua)                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  {
    'OXY2DEV/oxy-nvim', -- Условная зависимость для lazy-load
    lazy = true,
    dev = false,
  },
  keys = {
    { 'D', mode = 'n', desc = 'Fancy diagnostics hover' },
  },
  config = function()
    -- Динамические highlight-группы для диагностики
    local ok, hl = pcall(require, 'scripts.highlights')
    if ok then hl.setup() end

    -- Fancy diagnostics popup
    local ok2, diag = pcall(require, 'scripts.diagnostics')
    if ok2 then diag.setup() end
  end,
}
