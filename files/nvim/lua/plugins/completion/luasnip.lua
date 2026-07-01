-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ L3MON4D3/LuaSnip                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'L3MON4D3/LuaSnip', -- snippets engine
    version="2.*",
    config=function()
        local ls = require('luasnip')
        local types = require('luasnip.util.types')

        ls.config.set_config({
            history = true,
            updateevents = 'TextChanged,TextChangedI',
            enable_autosnippets = true,
            ext_opts = {
                [types.insertNode] = { active = { virt_text = { { '●', 'Operator' } } } },
                [types.choiceNode] = { active = { virt_text = { { '●', 'Constant' } } } },
            },
        })

        -- Snippet navigation keymaps
        vim.keymap.set({ 'i', 's' }, '<C-k>', function()
            if ls.jumpable(-1) then ls.jump(-1) end
        end, { silent = true, desc = 'LuaSnip: jump prev' })
        vim.keymap.set({ 'i', 's' }, '<C-j>', function()
            if ls.expand_or_jumpable() then ls.expand_or_jump() end
        end, { silent = true, desc = 'LuaSnip: expand/jump next' })
        vim.keymap.set({ 'i', 's' }, '<C-l>', function()
            if ls.choice_active() then ls.change_choice(1) end
        end, { desc = 'LuaSnip: cycle choice' })

        local function load(mod)
            local ok, m = pcall(require, mod)
            if ok then m.lazy_load() end
        end
        load('luasnip.loaders.from_vscode')
        load('luasnip.loaders.from_snipmate')
        load('luasnip.loaders.from_lua')
    end,
    dependencies={'rafamadriz/friendly-snippets',},
    event={'InsertEnter'}}
