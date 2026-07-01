-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mason.nvim — portable LSP/formatter/linter installer                        │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  {
    'mason-org/mason.nvim',
    cmd = { 'Mason', 'MasonInstall', 'MasonUpdate', 'MasonLog' },
    opts = {},
  },
  {
    'mason-org/mason-lspconfig.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      'mason-org/mason.nvim',
      'neovim/nvim-lspconfig',
    },
    opts = {
      automatic_enable = true,
      ensure_installed = {
        'autotools_ls',
        'bashls',
        'clangd',
        'cssls',
        'dotls',
        'html',
        'jsonls',
        'just',
        'lemminx',
        'lua_ls',
        'marksman',
        'pyright',
        'qmlls',
        'taplo',
        'ts_ls',
        'yamlls',
      },
    },
  },
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    event = 'VeryLazy',
    dependencies = { 'mason-org/mason.nvim' },
    opts = {
      ensure_installed = {
        'clang-format',
        'cmake-format',
        'prettierd',
        'ruff',
        'shellcheck',
        'shfmt',
        'stylua',
        'vale',
        'yamllint',
      },
    },
  },
}
