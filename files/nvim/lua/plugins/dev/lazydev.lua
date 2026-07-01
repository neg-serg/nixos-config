-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ folke/lazydev.nvim                                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    library = {
      -- luv/uv types for vim.uv
      { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      { path = "${3rd}/busted/library", words = { "describe", "it", "before_each", "after_each" } },
      { path = "${3rd}/luassert/library", words = { "assert" } },
      { path = "${3rd}/luafun/library", words = { "fun%." } },
    },

    fast = true,

    private = { "^_" },
  },
}
