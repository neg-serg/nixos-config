-- fk_markdown.nvim: lightweight Markdown rendering + live browser preview.
-- Fork/rewrite of render-markdown.nvim by the-mayankjha (module: fk_markdown).
-- Docs: README.md, doc/configuration.md; diagnostics: :checkhealth fk_markdown
--
-- All rendering subsystems are enabled explicitly: headings, code blocks,
-- tables, callouts/blockquotes, bullets, checkboxes, links (incl. wiki links),
-- thematic breaks, signs, org-style indent, inline highlights, LaTeX, images,
-- HTML, YAML frontmatter and PlantUML -- plus the web preview subsystem with
-- syntax highlighting, KaTeX math and on-demand keymaps (<leader>mp/ms/mt).
return {
  'the-mayankjha/fk_markdown.nvim',
  ft = { 'markdown', 'quarto', 'Avante', 'mdx' },
  config = function()
    require('fk_markdown').setup({
      preset = 'none', -- 'none' | 'obsidian' | 'lazy'

      -- ── In-editor rendering (all features on) ──────────────────
      heading = {
        enabled = true,
        icon = true,
        icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
        background = {
          enabled = true,
          bg_color = { '#1e1e2e', '#1e1e2e', '#1e1e2e', '#1e1e2e', '#1e1e2e', '#1e1e2e' },
          font_color = { '#f38ba8', '#fab387', '#f9e2af', '#a6e3a1', '#74c7ec', '#cba6f7' },
        },
      },
      code = {
        enabled = true,
        style = 'wide',
        border = { enabled = true, type = 'dynamic', color = '#f38ba8' },
        background = { enabled = true, color = '#181825' },
        padding = { top = 1, bottom = 1, left = 1, right = 2 },
        title = { enabled = true, type = 'dynamic', color = '#a6e3a1' },
        icon = { enabled = true },
      },
      pipe_table = {
        enabled = true,
        preset = 'none',
        style = 'full',
      },
      quote = {
        enabled = true,
        style = 'boxy',
        border = true,
        bg = 'NONE',
        fg = '#cad3f5',
      },
      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
      },
      checkbox = {
        enabled = true,
        unchecked = { icon = '󰄱 ', highlight = 'RenderMarkdownUnchecked' },
        checked = { icon = '󰱒 ', highlight = 'RenderMarkdownChecked' },
      },
      link = {
        enabled = true,
        wiki = { enabled = true },
        image = '󰥶 ',
        hyperlink = '󰌹 ',
      },
      dash = { enabled = true, icon = '─' },
      sign = { enabled = true },
      indent = { enabled = true, per_level = 2, skip_level = 1 },
      inline_highlight = { enabled = true },
      latex = { enabled = true },
      image = { enabled = true },
      html = { enabled = true },
      yaml = { enabled = true },
      plant_uml = { enabled = true },
      anti_conceal = { enabled = true },
      win_options = {
        conceallevel = { default = vim.o.conceallevel, rendered = 3 },
        concealcursor = { default = vim.o.concealcursor, rendered = '' },
      },

      -- blink.cmp source: completes callouts ([!NOTE]...) and checkboxes
      completions = { blink = { enabled = true } },

      -- ── Browser preview (separate subsystem) ───────────────────
      preview = {
        enabled = true,
        auto_start = false, -- start on demand via the keymaps below
        auto_close = true,
        auto_scroll = true,
        browser = '',
        open_ip = '127.0.0.1',
        port = nil,
        theme = 'dark',
        syntax_highlight = {
          enabled = true,
          theme = 'github-dark',
          colors = {
            background = '#181825',
            keyword = '#cba6f7',
            string = '#a6e3a1',
            comment = '#6c7086',
            function_name = '#89b4fa',
          },
        },
        latex = { enabled = true, code_blocks = true },
        plant_uml = {
          enabled = true,
          server = 'https://www.plantuml.com/plantuml',
          format = 'svg',
          theme = 'default',
          styling = { background = 'transparent', border = true, scale = 1.0 },
        },
        keymap = {
          start = '<leader>mp',
          stop = '<leader>ms',
          toggle = '<leader>mt',
        },
      },
    })
  end,
}
