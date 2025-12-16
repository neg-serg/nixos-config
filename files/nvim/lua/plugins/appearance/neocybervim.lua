-- │ █▓▒░ DonJulve/NeoCyberVim                                                    │
-- Colorscheme. Installed but not set as default; enable via
--   :lua require('NeoCyberVim').colorscheme()
-- or `vim.cmd.colorscheme('NeoCyberVim')`.
return {
  'DonJulve/NeoCyberVim',
  lazy = true,
  priority = 1000, -- allow opting-in before others
  opts = {
    transparent = false,
    italics = {
      comments = true,
      keywords = true,
      functions = true,
      strings = true,
      variables = true,
    },
    overrides = {},
  },
  config = function(_, opts)
    pcall(function() require('NeoCyberVim').setup(opts) end)
  end,
}

