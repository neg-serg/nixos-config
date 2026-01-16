-- │ █▓▒░ metalelf0/black-metal-theme-neovim                                      │
-- Collection of black-metal inspired themes. Installed but not set by default.
-- Enable with `:colorscheme bathory` (or other band) or require('black-metal').load().
return {
  'metalelf0/black-metal-theme-neovim',
  lazy = true,
  priority = 1000,
  config = function()
    -- Keep defaults; user can call :colorscheme <band> or .load()
    pcall(function()
      require('black-metal').setup({
        -- theme = 'bathory',
        -- variant = 'dark',
        -- alt_bg = false,
        -- transparent = false,
      })
    end)
  end,
}

