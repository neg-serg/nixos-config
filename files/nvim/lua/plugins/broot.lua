-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ 9999years/broot.nvim — broot file manager inside Neovim (floating terminal) │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  "9999years/broot.nvim",
  cmd = { "Broot" },
  keys = {
    { "<leader>fb", "<Cmd>Broot<CR>", desc = "Broot file manager (cwd)" },
    {
      "<leader>fB",
      function()
        require("broot").broot({
          directory = require("broot.default_directory").git_root(),
        })
      end,
      desc = "Broot file manager (git root)",
    },
  },
  -- Explicit config: lazy.nvim derives module "broot" from the repo name,
  -- but we name it out loud so setup() always runs with our opts.
  config = function(_, opts)
    require("broot").setup(opts)
  end,
  opts = {
    create_user_commands = true,
  },
}
