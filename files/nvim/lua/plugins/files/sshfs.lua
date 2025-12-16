-- │ █▓▒░ uhs-robert/sshfs.nvim                                                    │
-- Minimal SSHFS integration that auto-detects your picker (telescope/oil/yazi ...) 
-- Loads only if `sshfs` binary is available. Provides :SSHConnect/:SSHBrowse/etc.
return {
  "uhs-robert/sshfs.nvim",
  cond = function()
    return vim.fn.executable("sshfs") == 1
  end,
  cmd = { "SSHConnect", "SSHDisconnect", "SSHEdit", "SSHReload", "SSHBrowse", "SSHGrep" },
  opts = {
    -- Defaults are sensible; tweak minimal bits here if needed.
    mounts = {
      -- Keep default under $HOME/mnt to avoid surprises
      base_dir = vim.fn.expand("$HOME") .. "/mnt",
      unmount_on_exit = true,
    },
    ui = {
      file_picker = {
        auto_open_on_mount = true,
        preferred_picker = "auto", -- telescope/oil/yazi/... auto-detection
        fallback_to_netrw = true,
      },
    },
    -- Keep default key prefix <leader>m; integrates with which-key if present
  },
}

