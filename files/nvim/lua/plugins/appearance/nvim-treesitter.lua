-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-treesitter/nvim-treesitter                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nvim-treesitter/nvim-treesitter',
  event = { "BufReadPost", "BufNewFile" },
  config = function()
    require('nvim-treesitter.configs').setup({
      ensure_installed = {}, -- managed by Nix 
      highlight = { enable = true }, -- enable highlighting
      indent = { enable = true }, -- smart indentation
    })
  end
}
