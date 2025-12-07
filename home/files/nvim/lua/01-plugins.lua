local ok, nixCats = pcall(require, "nixCats")
local lazy
local lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json"
local doc_cache = vim.fn.stdpath("state") .. "/lazy-docs"

local plugin_tasks_ok, plugin_tasks = pcall(require, "lazy.manage.task.plugin")
if plugin_tasks_ok and plugin_tasks.docs then
    local orig_docs_run = plugin_tasks.docs.run
    plugin_tasks.docs.run = function(self)
        local docs = self.plugin.dir .. "/doc"
        if docs:match("^/nix/store/") then
            local dst = doc_cache .. "/" .. (self.plugin.name or "plugin")
            vim.fn.mkdir(dst, "p")
            -- copy doc dir into writable state cache to allow helptags
            vim.fn.system({ "cp", "-r", docs .. "/.", dst })
            docs = dst
        end
        return orig_docs_run(self)
    end
end
if ok and nixCats.lazy then
    lazy = nixCats.lazy
    lazy.setup({
        lockfile = lockfile,
        defaults = { lazy = false },
        install = { colorscheme = { "neg" } },
        ui = { icons = { ft = "", lazy = "󰂠 ", loaded = "", not_loaded = "" } },
        performance = {
            cache = { enabled = true },
            reset_packpath = true,
            rtp = { disabled_plugins = { "gzip", "matchparen", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
        },
    })
else
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
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
    lazy = require("lazy")
    lazy.setup({
        lockfile = lockfile,
        spec = { { import = "plugins" } },
        defaults = { lazy = false },
        install = { colorscheme = { "neg" } },
        ui = { icons = { ft = "", lazy = "󰂠 ", loaded = "", not_loaded = "" } },
        performance = {
            cache = { enabled = true },
            reset_packpath = true,
            rtp = { disabled_plugins = { "gzip", "matchparen", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
        },
    })
end
