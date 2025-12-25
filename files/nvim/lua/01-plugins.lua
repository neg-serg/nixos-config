if vim.g.lazy_did_setup then
    return
end

local ok, nixCats = pcall(require, "nixCats")
local lazy
local lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json"
local doc_cache = vim.fn.stdpath("state") .. "/lazy-docs"

local plugin_tasks_ok, plugin_tasks = pcall(require, "lazy.manage.task.plugin")
if plugin_tasks_ok and plugin_tasks.docs then
    local orig_docs_run = plugin_tasks.docs.run
    plugin_tasks.docs.run = function(self)
        local orig_dir = self.plugin.dir
        local docs = orig_dir .. "/doc"

        if docs:match("^/nix/store/") then
            local dst = doc_cache .. "/" .. (self.plugin.name or "plugin")
            vim.fn.mkdir(dst, "p")
            -- copy doc dir into writable state cache to allow helptags
            if vim.loop.fs_stat(docs) then
                vim.fn.system({ "cp", "-r", docs .. "/.", dst })
            end
            self.plugin.dir = dst -- run helptags in writable cache
        end

        local ok, err = pcall(orig_docs_run, self)
        self.plugin.dir = orig_dir
        if not ok then
            error(err)
        end
        return ok
    end
end
if ok and nixCats.lazy then
    lazy = nixCats.lazy
    lazy.setup({
        lockfile = lockfile,
        defaults = { lazy = true },
        install = { colorscheme = { "neg" } },
        rocks = { enabled = false },
        ui = { icons = { ft = "", lazy = "󰂠 ", loaded = "", not_loaded = "" } },
        performance = {
            cache = { enabled = true },
            reset_packpath = false,
            rtp = { disabled_plugins = { "gzip", "matchparen", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
        },
    })
else
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    -- Check if lazy is already available (e.g. from nvf startPlugins)
    local lazy_present, _ = pcall(require, "lazy")
    
    if not lazy_present then
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
    else
        lazy = require("lazy")
    end
    
    lazy.setup({
        lockfile = lockfile,
        spec = { { import = "plugins" } },
        defaults = { lazy = true },
        install = { colorscheme = { "neg" } },
        rocks = { enabled = false },
        ui = { icons = { ft = "", lazy = "󰂠 ", loaded = "", not_loaded = "" } },
        performance = {
            cache = { enabled = true },
            reset_packpath = false,
            rtp = { disabled_plugins = { "gzip", "matchparen", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin" } },
        },
    })
end
