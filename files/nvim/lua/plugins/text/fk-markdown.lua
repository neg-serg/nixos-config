-- fk_markdown.nvim: lightweight Markdown rendering + live browser preview.
-- Fork/rewrite of render-markdown.nvim by the-mayankjha (module: fk_markdown).
-- Docs: README.md, doc/configuration.md; diagnostics: :checkhealth fk_markdown
--
-- Colors are tuned to the neg.nvim palette (~/.local/share/nvim/lazy/neg.nvim/
-- lua/neg/palette.lua):
--   heading ramp  = neg markup heading ramp (accent_secondary #005faf blended
--                   with include #005f87; exact values from neg.util lighten/
--                   darken)  ->  #669fcf #4087c3 #005faf #005f87 #005173 #00435f
--   code bg       = p.dark       #121212
--   code border   = p.drk2       #223f73
--   code title    = p.func       #7095b0
--   quote fg      = p.norm       #6c7e96
--   checkbox hl   = neg groups @markup.list.checked / .unchecked
--   preview bg    = p.dark; keyword/string/comment/function = neg syntax hues
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
        width = 'block', -- heading background spans only the text width
        border = true, -- horizontal lines above/below headings
        background = {
          enabled = true,
          bg_color = {
            '#121212', '#121212', '#121212',
            '#121212', '#121212', '#121212',
          },
          font_color = {
            '#669fcf', '#4087c3', '#005faf',
            '#005f87', '#005173', '#00435f',
          },
        },
      },
      paragraph = {
        enabled = true,
        left_margin = 2, -- indent each paragraph (org-like)
      },
      code = {
        enabled = true,
        style = 'wide',
        border = { enabled = true, type = 'dynamic', color = '#223f73' },
        background = { enabled = true, color = '#121212' },
        padding = { top = 1, bottom = 1, left = 1, right = 2 },
        title = { enabled = true, type = 'dynamic', color = '#7095b0' },
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
        fg = '#6c7e96',
      },
      bullet = {
        enabled = true,
        icons = { '●', '○', '◆', '◇' },
      },
      checkbox = {
        enabled = true,
        unchecked = { icon = '󰄱 ', highlight = '@markup.list.unchecked' },
        checked = { icon = '󰱒 ', highlight = '@markup.list.checked' },
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
      anti_conceal = {
        enabled = true,
        above = 1, -- keep the line above the cursor rendered
        below = 1, -- keep the line below the cursor rendered
      },
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
            background = '#121212',
            keyword = '#669fcf',
            string = '#6e879f',
            comment = '#3c4754',
            function_name = '#7095b0',
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
