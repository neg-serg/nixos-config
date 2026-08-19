-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Saghen/blink.cmp                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'saghen/blink.cmp',
  event = { "BufReadPre", "BufNewFile", "CmdlineEnter" },
  version = '1.*', -- use a release tag to download pre-built binaries
  opts = {
    keymap = {
      preset = 'super-tab',
      ['<C-Space>'] = { 'show', 'select_next', 'fallback' },
    },
    appearance = { nerd_font_variant = 'mono'},
    completion = { documentation = { auto_show = true, auto_show_delay_ms = 200 } },
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer', 'continue' },
    },
    fuzzy = { implementation = "prefer_rust" },
  },
  opts_extend = { "sources.default" }
}
