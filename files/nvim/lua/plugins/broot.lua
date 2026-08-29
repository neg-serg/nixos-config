-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ broot — vendored 9999years/broot.nvim (see lua/broot/)                      │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- Eager (no git fetch): the plugin is vendored under lua/broot/ and opens in a
-- vertical split by default so the current buffer stays visible.
--
--   E             broot in vsplit at the current file's directory
--   <leader>fb    same as E
--   <leader>fB    broot in vsplit at the git root
--   :Broot [dir]  broot in vsplit at cwd (or the given directory)
--   Inside broot: enter = open here, ctrl-v = vsplit, ctrl-x = hsplit,
--   ctrl-t = new tab, alt-enter = cd, alt-up = parent, alt-down = open.
local broot = require("broot")

broot.setup {
  create_user_commands = true,
  layout = "vsplit",
  -- nvim.toml FIRST: broot resolves duplicate keys by first match, so the
  -- in-nvim overrides (enter/ctrl-v/ctrl-x/ctrl-t) beat conf.toml verbs
  -- (e.g. ctrl-t = $EDITOR) inside the nvim-launched broot session.
  config_files = {
    "~/.config/broot/nvim.toml",
    "~/.config/broot/conf.toml",
  },
}

local function current_file_dir()
  local dir = require("broot.default_directory").current_file()
  return (dir ~= "" and dir) or nil
end

local function open_vsplit(dir)
  broot.broot { directory = dir, layout = "vsplit" }
end

vim.keymap.set("n", "E", function()
  open_vsplit(current_file_dir())
end, { desc = "Broot (vsplit, current file)" })

vim.keymap.set("n", "<leader>fb", function()
  open_vsplit(current_file_dir())
end, { desc = "Broot: current file's dir" })

vim.keymap.set("n", "<leader>fB", function()
  open_vsplit(require("broot.default_directory").git_root())
end, { desc = "Broot: git root" })

return {}
