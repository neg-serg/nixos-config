local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    -- Config dir is a read-only nix store link (~/.config/nvim), so the live
    -- lock must live in state. The committed lazy-lock.json in the repo is a
    -- pin snapshot: refresh it manually after :Lazy sync if you want to track
    -- the latest versions (cp ~/.local/state/nvim/lazy-lock.json files/nvim/).
    lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
    spec = { { import = "plugins" } },
    defaults = { lazy = true },
    install = { colorscheme = { "neg" } },
    rocks = { enabled = false },
    ui = { icons = { ft = "", lazy = "󰂠 ", loaded = "", not_loaded = "" } },
    performance = {
        cache = { enabled = true },
        reset_packpath = false,
        rtp = { disabled_plugins = { "gzip", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
    },
})
