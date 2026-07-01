-- File plugins: sshfs, vim-fetch, yazi
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

  -- │ █▓▒░ mikavilpas/yazi.nvim                                                     │
  {
    "mikavilpas/yazi.nvim",
    keys = {
      { "<leader>-", function() require("yazi").yazi() end, desc = "Open yazi at the current file" },
      { "<leader>cw", function() require("yazi").yazi(nil, vim.fn.getcwd()) end, desc = "Open yazi in cwd" },
    },
    init = function()
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(args)
          if vim.b[args.buf]._yazi_checked then return end
          vim.b[args.buf]._yazi_checked = true
          if not vim.bo[args.buf].buflisted then return end
          if vim.bo[args.buf].buftype ~= "" then return end
          if vim.fn.isdirectory(vim.api.nvim_buf_get_name(args.buf)) == 1 then
            require("lazy").load({ plugins = { "yazi.nvim" } })
            return true
          end
        end,
      })
    end,
    opts = {
      open_for_directories = true,
      floating_window_scaling_factor = 1.0,
      yazi_floating_window_border = "none",
      keymaps = {
        open_file_in_vertical_split = "<c-v>",
        open_file_in_horizontal_split = "<c-x>",
        open_file_in_tab = "<c-t>",
        grep_in_directory = "<c-f>",
        replace_in_directory = "<c-g>",
        cycle_open_buffers = "<NOP>",
        copy_relative_path_to_selected_files = "<c-y>",
        send_to_quickfix_list = "<c-q>",
        change_working_directory = "<tab>",
      },
    },
  },
}
