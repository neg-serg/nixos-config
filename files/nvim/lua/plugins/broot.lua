-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ 9999years/broot.nvim — broot file manager inside Neovim (floating terminal) │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- Usage:
--   <leader>fb     broot at the current file's directory
--   <leader>fB     broot at the git root of the current file
--   :Broot [dir]   broot at cwd (or the given directory)
--   Inside broot: enter = open in current window, ctrl-v = vsplit,
--   ctrl-x = hsplit, ctrl-t = new tab, alt-enter = cd (verbs in
--   files/shell/broot/nvim.toml, mirroring yazi.nvim keys).
return {
  "9999years/broot.nvim",
  cmd = { "Broot" },
  keys = {
    {
      "<leader>fb",
      function()
        local dir = require("broot.default_directory").current_file()
        require("broot").broot({ directory = (dir ~= "" and dir) or nil })
      end,
      desc = "Broot: current file's dir",
    },
    {
      "<leader>fB",
      function()
        require("broot").broot({
          directory = require("broot.default_directory").git_root(),
        })
      end,
      desc = "Broot: git root",
    },
  },
  config = function(_, opts)
    require("broot").setup(opts)
  end,
  opts = {
    create_user_commands = true,
    -- nvim.toml FIRST: broot resolves duplicate keys by first match, so the
    -- in-nvim overrides (enter/ctrl-v/ctrl-x/ctrl-t) beat conf.toml verbs
    -- (e.g. ctrl-t = $EDITOR) inside the nvim-launched broot session.
    config_files = {
      "~/.config/broot/nvim.toml",
      "~/.config/broot/conf.toml",
    },
  },
}
