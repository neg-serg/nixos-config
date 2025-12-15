-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ folke/flash.nvim                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "folke/flash.nvim",
  event = "VeryLazy",
  enabled = true,
  opts = {
    modes = {
      search = {
        enabled = false,
      },
    },
  },
  keys = {
    {
      "<space>",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump()
      end,
      desc = "Flash",
    },
  },
}
