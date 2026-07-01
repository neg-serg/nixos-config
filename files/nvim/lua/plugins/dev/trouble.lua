-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ folke/trouble.nvim                                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'folke/trouble.nvim', -- pretty list for diagnostics
    dependencies={'nvim-tree/nvim-web-devicons'},
    cmd={'Trouble'},
    opts={},
    keys={
        {'<leader>x', '<cmd>Trouble diagnostics toggle<cr>', desc='Diagnostics (Trouble)'},
    },
}
