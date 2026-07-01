-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-neorg/neorg                                                             │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'nvim-neorg/neorg',
    ft = 'norg',
    cmd = 'Neorg',
    config = function()
        require('neorg').setup({
            load = {
                ['core.defaults'] = {},
                ['core.concealer'] = {},
                ['core.dirman'] = {
                    config = {
                        workspaces = { notes = '~/notes/org' },
                        default_workspace = 'notes',
                    },
                },
            },
        })
    end,
}
