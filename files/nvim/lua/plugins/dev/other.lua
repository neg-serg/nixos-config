-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░  rgroli/other.nvim                                                           │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'rgroli/other.nvim', -- Open alternative files for the current buffer
    config=function()
        require'other-nvim'.setup({
            mappings = {
            },
        })
    end
}
