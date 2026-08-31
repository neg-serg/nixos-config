-- fk_markdown.nvim: lightweight Markdown rendering + live browser preview.
-- Fork/rewrite of render-markdown.nvim by the-mayankjha (module: fk_markdown).
-- Docs: README.md, doc/configuration.md; diagnostics: :checkhealth fk_markdown
return {
  'the-mayankjha/fk_markdown.nvim',
  ft = { 'markdown', 'quarto', 'Avante', 'mdx' },
  config = function()
    require('fk_markdown').setup({
      preset = 'none', -- 'none' | 'obsidian' | 'lazy'

      -- In-editor rendering (defaults already on; tuning examples)
      heading = { enabled = true, icon = true },
      checkbox = { enabled = true },
      link = { enabled = true, wiki = { enabled = true } }, -- [[x]] / [[x|alias]]

      -- Browser preview (separate subsystem; start via :FkPreview / keymap)
      preview = {
        enabled = true,
        auto_start = false, -- start only on demand
        auto_close = true,
        auto_scroll = true,
        theme = 'dark',
        keymap = {
          start = '<leader>mp',
          stop = '<leader>ms',
          toggle = '<leader>mt',
        },
      },
    })
  end,
}
