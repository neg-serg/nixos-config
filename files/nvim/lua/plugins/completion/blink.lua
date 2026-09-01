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
      default = { 'lsp', 'path', 'snippets', 'buffer', 'partial_completion' }, -- (continue removed: plugin ships no nvim client)
      providers = {
        partial_completion = {
          name = 'Partial Completion',
          module = 'partial_completion.adapters.blink',
          async = true,
          opts = {
            auto_highlight = true,
            request = { limit = 100 },
          },
        },
      },
    },
    cmdline = {
      -- blink cmdline defaults are { 'buffer', 'cmdline' }; partial_completion added
      sources = { 'buffer', 'cmdline', 'partial_completion' },
    },
    fuzzy = { implementation = "prefer_rust" },
  },
  opts_extend = { "sources.default" }
}
