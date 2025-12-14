-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-treesitter/nvim-treesitter                                              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate', -- чтобы автоматически обновлялись парсеры
  config = function()
    require('nvim-treesitter.configs').setup({
      ensure_installed = {
        "bash",
        "caddy",
        "cmake",
        "css",
        "diff",
        "dockerfile",
        "gitcommit",
        "gitignore",
        "glsl",
        "go",
        "gomod",
        "gosum",
        "graphql",
        "html",
        "http",
        "ini",
        "javascript",
        "json",
        "just",
        "kconfig",
        "lua",
        "luadoc",
        "make",
        "markdown",
        "markdown_inline",
        "meson",
        "ninja",
        "nix",
        "php",
        "python",
        "query",
        "regex",
        "scss",
        "sql",
        "svelte",
        "toml",
        "vim",
        "vimdoc",
        "vue",
        "wgsl",
        "xml",
        "yaml",
      },
      highlight = { enable = true }, -- включить подсветку
      indent = { enable = true }, -- умные отступы
    })
  end
}
