-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ delphinus/md-render.nvim                                                     │
-- └───────────────────────────────────────────────────────────────────────────────────┘

-- Terminal Markdown renderer (float / tab / source-render split / pager). It renders
-- into a separate read-only buffer, so fk_markdown.nvim keeps the in-buffer view and
-- its ,mp/,ms/,mt keys; md-render takes the free ,mr/,mR/,mv slots.
--
-- Needs Neovim >= 0.12 (we run 0.13 nightly) and the Kitty graphics protocol for
-- inline images (this terminal is kitty). ffmpeg and curl already come from the
-- system closure: JPEG/WebP conversion, animated GIF and video frames, web media.
-- Mermaid needs mmdc and PlantUML needs a local renderer, so without them those
-- fences stay treesitter-highlighted code blocks.
return {
  'delphinus/md-render.nvim',
  version = '*',
  cmd = 'MdRender',
  dependencies = { 'nvim-tree/nvim-web-devicons' }, -- ft icons in code block headers
  keys = {
    { '<leader>mr', '<Cmd>MdRender float<CR>', desc = 'Markdown render (float, toggle)' },
    { '<leader>mR', '<Cmd>MdRender tab<CR>', desc = 'Markdown render (tab, toggle)' },
    { '<leader>mv', '<Cmd>vert MdRender split<CR>', desc = 'Markdown render (source/render split)' },
  },
}
