-- File plugins: yazi, sshfs, vim-fetch
--
-- yazi is THE file manager of this config: the old LustyExplorer filesystem
-- keys (,l / ,C), the snacks smart-find key (ee) and cwd-open (_) all launch
-- yazi now, and any directory buffer (nvim <dir>, :e <dir>) is redirected to
-- it too. LustyExplorer keeps its buffer/grep/recent pickers (:Lusty*), snacks
-- keeps the pure file finders (,ff / ,e / gz / ,L).
return {
  -- │ █▓▒░ mikavilpas/yazi.nvim                                                      │
  -- yazi in a floating window; the keys pressed inside it are yazi.nvim's own
  -- (opts.keymaps), so yazi's stock bindings stay reachable in the tree.
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>l",  function() require("yazi").yazi() end, desc = "Yazi: current file's dir" },
      { "<leader>fb", function() require("yazi").yazi() end, desc = "Yazi: current file's dir" },
      { "<leader>fB", function() require("yazi").yazi(nil, require("utils.fzf").project_root()) end, desc = "Yazi: project root (git)" },
      { "<leader>C",  function() require("yazi").yazi(nil, vim.fn.getcwd()) end, desc = "Yazi: working dir" },
      { "<leader>fm", function() require("yazi").yazi(nil, vim.fn.getcwd()) end, desc = "Yazi: working dir (file manager)" },
      { "ee",         function() require("yazi").yazi(nil, vim.fn.getcwd()) end, desc = "Files (yazi)" },
      { "_",          function() require("yazi").yazi(nil, vim.fn.getcwd()) end, desc = "Open cwd (yazi)" },
    },
    -- netrw is disabled (01-plugins.lua), so `nvim <dir>` / `:e <dir>` would
    -- leave a dead directory buffer: `open_for_directories` hands it to yazi,
    -- including the buffer that already exists when nvim starts on a
    -- directory. Marking netrw as loaded is what yazi.nvim asks for in that
    -- mode (documentation/installation); it is already disabled above.
    init = function()
      vim.g.loaded_netrwPlugin = 1
    end,
    opts = {
      open_for_directories = true,
      floating_window_scaling_factor = 1.0,
      yazi_floating_window_border = "none",
      keymaps = {
        open_file_in_vertical_split = "<c-v>",
        open_file_in_horizontal_split = "<c-x>",
        open_file_in_tab = "<c-t>",
        -- Keep clear of the yazi keymap in modules/user/nix-maid/cli/yazi.nix:
        -- <c-f>, <c-s> and <c-q> already mean enter/confirm/close there, so the
        -- nvim-side actions take keys yazi itself does not use.
        grep_in_directory = "<c-g>",
        replace_in_directory = "<c-r>",
        copy_relative_path_to_selected_files = "<c-y>",
        cycle_open_buffers = false,
        send_to_quickfix_list = false,
        change_working_directory = false,
      },
      integrations = {
        -- snacks is the picker of record here (plugins/ui/snacks.lua).
        grep_in_directory = "snacks.picker",
        grep_in_selected_files = "snacks.picker",
      },
    },
  },

  -- │ █▓▒░ uhs-robert/sshfs.nvim                                                   │
  {
    "uhs-robert/sshfs.nvim",
    enabled = function() return vim.fn.executable("sshfs") == 1 end,
    cmd = { "SSHConnect", "SSHDisconnect", "SSHEdit", "SSHReload", "SSHBrowse", "SSHGrep" },
    opts = {
      mounts = {
        base_dir = vim.fn.expand("$HOME") .. "/mnt",
        unmount_on_exit = true,
      },
      ui = {
        file_picker = {
          auto_open_on_mount = true,
          preferred_picker = "auto",
          fallback_to_netrw = true,
        },
      },
    },
  },

  -- │ █▓▒░ wsdjeg/vim-fetch                                                         │
  {'wsdjeg/vim-fetch', lazy = false}, -- must load before BufRead to intercept file:line paths

}
