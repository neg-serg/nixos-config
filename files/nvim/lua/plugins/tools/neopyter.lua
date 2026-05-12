return {
  "SUSTech-data/neopyter",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "AbaoFromCUG/websocket.nvim",
  },
  ft = { "python", "markdown" },
  opts = {
    mode = "direct",
    remote_address = "127.0.0.1:9001",
    file_pattern = { "*.ju.*", "*.ipynb" },
    on_attach = function(bufnr)
      local function map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { desc = desc, buffer = bufnr })
      end
      map("n", "<C-Enter>", "<cmd>Neopyter execute notebook:run-cell<cr>", "Run cell")
      map("n", "<S-Enter>", "<cmd>Neopyter execute notebook:run-cell-and-select-next<cr>", "Run cell and select next")
      map("n", "<space>X", "<cmd>Neopyter execute notebook:run-all-above<cr>", "Run all above")
    end,
  },
}
