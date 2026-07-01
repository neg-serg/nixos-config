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
