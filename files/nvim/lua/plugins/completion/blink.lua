-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Saghen/blink.cmp                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'saghen/blink.cmp',
  event = { "InsertEnter", "CmdlineEnter" },
  lazy = true,
  dependencies = { 'rafamadriz/friendly-snippets' }, -- optional: provides snippets for the snippet source
  version = '1.*', -- use a release tag to download pre-built binaries
  -- build = 'nix run .#build-plugin',
  opts = {
    keymap = { preset = 'super-tab' }, -- See :h blink-cmp-config-keymap for defining your own keymap
    appearance = { nerd_font_variant = 'mono'},
    completion = { documentation = { auto_show = false } }, -- (Default) Only show the documentation popup when manually triggered
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer', 'minuet' },
      providers = {
        minuet = {
          name = 'minuet',
          module = 'minuet.blink',
          score_offset = 100,
        },
      },
    },
    fuzzy = { implementation = "prefer_rust_with_warning" },
  },
  opts_extend = { "sources.default" }
}
