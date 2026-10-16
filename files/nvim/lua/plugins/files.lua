-- File plugins: broot, sshfs, vim-fetch
--
-- broot is THE file manager of this config: the old LustyExplorer filesystem
-- keys (,l / ,C), the snacks smart-find key (ee) and cwd-open (_) all launch
-- broot now, and any directory buffer (nvim <dir>, :e <dir>) is redirected to
-- it too. LustyExplorer keeps its buffer/grep/recent pickers (:Lusty*), snacks
-- keeps the pure file finders (,ff / ,e / gz / ,L).
return {
  -- │ █▓▒░ aohoyd/broot.nvim                                                        │
  -- broot in a floating terminal; Enter on a file runs `echo +{line} {file}` and
  -- the plugin opens the echoed path (upstream lua/broot/init.lua parse_lines).
  {
    "aohoyd/broot.nvim",
    enabled = function() return vim.fn.executable("broot") == 1 end,
    cmd = { "Broot", "BrootCurrentDir", "BrootWorkingDir", "BrootHomeDir", "BrootProjectDir" },
    keys = {
      { "<leader>l",  "<Cmd>BrootCurrentDir<CR>", desc = "Broot: current file's dir" },
      { "<leader>fb", "<Cmd>BrootCurrentDir<CR>", desc = "Broot: current file's dir" },
      { "<leader>fB", "<Cmd>BrootProjectDir<CR>", desc = "Broot: project root (git)" },
      { "<leader>C",  "<Cmd>BrootWorkingDir<CR>", desc = "Broot: working dir" },
      { "<leader>fm", "<Cmd>BrootWorkingDir<CR>", desc = "Broot: working dir (file manager)" },
      { "ee",         "<Cmd>BrootWorkingDir<CR>", desc = "Files (broot)" },
      { "_",          "<Cmd>BrootWorkingDir<CR>", desc = "Open cwd (broot)" },
    },
    -- netrw is disabled (01-plugins.lua), so `nvim <dir>` / `:e <dir>` would
    -- leave a dead directory buffer: hand every such buffer to broot instead
    -- (the full replacement for vim's file browser). Registered in `init` so
    -- it is active from startup, while the plugin itself stays lazy: broot is
    -- only loaded when a directory is actually opened.
    init = function()
      vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("BrootDirHijack", { clear = true }),
        desc = "Open directory buffers in broot",
        callback = function(args)
          if vim.api.nvim_get_current_buf() ~= args.buf or vim.bo[args.buf].buftype ~= "" then
            return
          end
          local name = vim.api.nvim_buf_get_name(args.buf)
          if name == "" or vim.fn.isdirectory(name) == 0 then
            return
          end
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(args.buf)
              or vim.api.nvim_get_current_buf() ~= args.buf then
              return
            end
            local ok, broot = pcall(require, "broot")
            if not ok or type(broot.open) ~= "function" then
              return
            end
            -- Drop the dead directory listing before broot takes over: an
            -- empty placeholder keeps the window valid, and re-entering it
            -- (e.g. after closing broot) cannot re-trigger this autocmd.
            vim.bo[args.buf].bufhidden = "wipe"
            vim.cmd("enew")
            broot.open(name)
          end)
        end,
      })
    end,
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
