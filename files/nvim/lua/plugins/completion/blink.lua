-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Saghen/blink.cmp                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'saghen/blink.cmp',
  event = { "BufReadPre", "BufNewFile", "CmdlineEnter" },
  dependencies = { 'rafamadriz/friendly-snippets' }, -- optional: provides snippets for the snippet source
  version = '1.*', -- use a release tag to download pre-built binaries
  opts = {
    keymap = { preset = 'super-tab' }, -- See :h blink-cmp-config-keymap for defining your own keymap
    appearance = { nerd_font_variant = 'mono'},
    completion = { documentation = { auto_show = true, auto_show_delay_ms = 200 } },
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
    },
    fuzzy = { implementation = "prefer_rust" },
  },
  opts_extend = { "sources.default" }
}
