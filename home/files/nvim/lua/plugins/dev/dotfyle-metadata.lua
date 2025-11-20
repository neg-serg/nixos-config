-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ creativenull/dotfyle-metadata.nvim                                          │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "creativenull/dotfyle-metadata.nvim",
  cmd = { "DotfyleGenerate", "DotfyleOpen" },
  keys = {
    { "<leader>ud", "<cmd>DotfyleGenerate<CR>", desc = "Dotfyle: generate metadata" },
    { "<leader>uD", "<cmd>DotfyleGenerate --keymaps<CR>", desc = "Dotfyle: include keymaps" },
  },
}
