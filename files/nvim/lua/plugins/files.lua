-- File plugins: sshfs, vim-fetch
return {
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
