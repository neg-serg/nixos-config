return {
  -- │ █▓▒░ esmuellert/codediff.nvim — VSCode-style diff rendering                  │
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    keys = {
      { "<leader>gd", "<cmd>CodeDiff<CR>", desc = "Diff (codediff)" },
      { "<leader>gh", "<cmd>CodeDiff history<CR>", desc = "Diff history (codediff)" },
    },
    opts = {
      diff = {
        layout = "side-by-side",
        jump_to_first_change = true,
        compact_context_lines = 3,
      },
      explorer = {
        position = "left",
        width = 35,
        flatten_dirs = true,
      },
      keymaps = {
        view = {
          quit = "q",
          toggle_layout = "t",
        },
      },
    },
  },
}
