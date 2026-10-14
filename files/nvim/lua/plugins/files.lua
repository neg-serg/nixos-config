-- File plugins: broot, sshfs, vim-fetch
return {
  -- │ █▓▒░ aohoyd/broot.nvim                                                        │
  -- broot in a floating terminal; Enter on a file runs `echo +{line} {file}` and
  -- the plugin opens the echoed path (upstream lua/broot/init.lua parse_lines).
  {
    "aohoyd/broot.nvim",
    enabled = function() return vim.fn.executable("broot") == 1 end,
    cmd = { "Broot", "BrootCurrentDir", "BrootWorkingDir", "BrootHomeDir", "BrootProjectDir" },
    opts = {
      -- The repo broot conf is TOML (files/shell/broot/conf.toml); the verb file
      -- the plugin appends is TOML too — broot picks the parser per file
      -- extension, so a mixed --conf list is fine.
      broot_conf_path = vim.fn.expand("~/.config/broot/conf.toml"),
      broot_vim_conf_path = vim.fn.expand(vim.fn.stdpath("data") .. "/broot.nvim/conf_nvim.toml"),
      broot_vim_conf = {
        "[[verbs]]",
        'key = "enter"',
        'external = "echo +{line} {file}"',
        'apply_to = "file"',
      },
      -- The plugin splices 'shellredir' into the command line as-is, but nvim
      -- defaults it to ">%s 2>&1": the literal %s would eat the redirect and the
      -- tmp file would come out as broot's second root argument.
      shellredir = ">",
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
